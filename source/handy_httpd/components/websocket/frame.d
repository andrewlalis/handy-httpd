/**
 * Contains the low-level implementation of the WebSocket data frame spec,
 * as well as some friendly functions for reading and writing data frames
 * from D types.
 */
module handy_httpd.components.websocket.frame;

import handy_httpd.components.websocket.handler : WebSocketException;
import streams;
import slf4d;

/**
 * An enumeration of valid opcodes for websocket data frames.
 * https://datatracker.ietf.org/doc/html/rfc6455#section-5.2
 */
enum WebSocketFrameOpcode : ubyte {
    CONTINUATION = 0,
    TEXT_FRAME = 1,
    BINARY_FRAME = 2,
    // 0x3-7 reserved for future non-control frames.
    CONNECTION_CLOSE = 8,
    PING = 9,
    PONG = 10
    // 0xB-F are reserved for further control frames.
}

/**
 * An enumeration of possible closing status codes for websocket connections,
 * as per https://datatracker.ietf.org/doc/html/rfc6455#section-7.4
 */
enum WebSocketCloseStatusCode : ushort {
    NORMAL = 1000,
    GOING_AWAY = 1001,
    PROTOCOL_ERROR = 1002,
    UNACCEPTABLE_DATA = 1003,
    NO_CODE = 1005,
    CLOSED_ABNORMALLY = 1006,
    INCONSISTENT_DATA = 1007,
    POLICY_VIOLATION = 1008,
    MESSAGE_TOO_BIG = 1009,
    EXTENSION_NEGOTIATION_FAILURE = 1010,
    UNEXPECTED_CONDITION = 1011,
    TLS_HANDSHAKE_FAILURE = 1015
}

/**
 * Internal intermediary structure used to hold the results of parsing a
 * websocket frame.
 */
struct WebSocketFrame {
    bool finalFragment;
    WebSocketFrameOpcode opcode;
    ubyte[] payload;
}

void sendWebSocketTextFrame(S)(S stream, string text) if (isByteOutputStream!S) {
    sendWebSocketFrame!S(
        stream,
        WebSocketFrame(true, WebSocketFrameOpcode.TEXT_FRAME, cast(ubyte[]) text)
    );
}

void sendWebSocketBinaryFrame(S)(S stream, ubyte[] bytes) if (isByteOutputStream!S) {
    sendWebSocketFrame!S(
        stream,
        WebSocketFrame(true, WebSocketFrameOpcode.BINARY_FRAME, bytes)
    );
}

void sendWebSocketCloseFrame(S)(S stream, WebSocketCloseStatusCode code, string message) {
    auto bufferOut = byteArrayOutputStream();
    auto dOut = dataOutputStreamFor(&bufferOut);
    dOut.writeToStream!ushort(code);
    if (message !is null && message.length > 0) {
        if (message.length > 123) {
            throw new WebSocketException("Close message is too long! Maximum of 123 bytes allowed.");
        }
        bufferOut.writeToStream(cast(ubyte[]) message);
    }
    sendWebSocketFrame!S(
        stream,
        WebSocketFrame(true, WebSocketFrameOpcode.CONNECTION_CLOSE, bufferOut.toArrayRaw())
    );
}

void sendWebSocketPingFrame(S)(S stream, ubyte[] payload) if (isByteOutputStream!S) {
    sendWebSocketFrame!S(
        stream,
        WebSocketFrame(true, WebSocketFrameOpcode.PING, payload)
    );
}

void sendWebSocketPongFrame(S)(S stream, ubyte[] pingPayload) if (isByteOutputStream!S) {
    sendWebSocketFrame!S(
        stream,
        WebSocketFrame(true, WebSocketFrameOpcode.PONG, pingPayload)
    );
}

/**
 * Sends a websocket frame to a byte output stream.
 * Params:
 *   stream = The stream to write to.
 *   frame = The frame to write.
 */
void sendWebSocketFrame(S)(S stream, WebSocketFrame frame) if (isByteOutputStream!S) {
    static if (isPointerToStream!S) {
        S ptr = stream;
    } else {
        S* ptr = &stream;
    }
    ubyte finAndOpcode = frame.opcode;
    if (frame.finalFragment) {
        finAndOpcode |= 128;
    }
    writeDataOrThrow(ptr, finAndOpcode);
    if (frame.payload.length < 126) {
        writeDataOrThrow(ptr, cast(ubyte) frame.payload.length);
    } else if (frame.payload.length <= ushort.max) {
        writeDataOrThrow(ptr, cast(ubyte) 126);
        writeDataOrThrow(ptr, cast(ushort) frame.payload.length);
    } else {
        writeDataOrThrow(ptr, cast(ubyte) 127);
        writeDataOrThrow(ptr, cast(ulong) frame.payload.length);
    }
    StreamResult result = stream.writeToStream(cast(ubyte[]) frame.payload);
    if (result.hasError) {
        throw new WebSocketException(cast(string) result.error.message);
    } else if (result.count != frame.payload.length) {
        import std.format : format;
        throw new WebSocketException(format!"Wrote %d bytes instead of expected %d."(
            result.count, frame.payload.length
        ));
    }
}

/**
 * Receives a websocket frame from a byte input stream.
 * Params:
 *   stream = The stream to receive from.
 * Returns: The frame that was received.
 */
WebSocketFrame receiveWebSocketFrame(S)(S stream) if (isByteInputStream!S) {
    static if (isPointerToStream!S) {
        S ptr = stream;
    } else {
        S* ptr = &stream;
    }
    auto finalAndOpcode = parseFinAndOpcode(ptr);
    immutable bool finalFragment = finalAndOpcode.finalFragment;
    immutable ubyte opcode = finalAndOpcode.opcode;
    immutable bool isControlFrame = (
        opcode == WebSocketFrameOpcode.CONNECTION_CLOSE ||
        opcode == WebSocketFrameOpcode.PING ||
        opcode == WebSocketFrameOpcode.PONG
    );

    immutable ubyte maskAndLength = readDataOrThrow!(ubyte)(ptr);
    immutable bool payloadMasked = (maskAndLength & 128) > 0;
    immutable ubyte initialPayloadLength = maskAndLength & 127;
    debugF!"Websocket data frame Mask bit = %s, Initial payload length = %d"(payloadMasked, initialPayloadLength);
    ulong payloadLength = readPayloadLength(initialPayloadLength, ptr);
    if (isControlFrame && payloadLength > 125) {
        throw new WebSocketException("Control frame payload is too large.");
    }

    ubyte[4] maskingKey;
    if (payloadMasked) maskingKey = readDataOrThrow!(ubyte[4])(ptr);
    debugF!"Receiving websocket frame: (FIN=%s,OP=%d,MASK=%s,LENGTH=%d)"(
        finalFragment,
        opcode,
        payloadMasked,
        payloadLength
    );
    ubyte[] buffer = readPayload(payloadLength, ptr);
    if (payloadMasked) unmaskData(buffer, maskingKey);

    return WebSocketFrame(
        finalFragment,
        cast(WebSocketFrameOpcode) opcode,
        buffer
    );
}

/**
 * Parses the `finalFragment` flag and opcode from a websocket frame's first
 * header byte.
 * Params:
 *   stream = The stream to read a byte from.
 */
private auto parseFinAndOpcode(S)(S stream) if (isByteInputStream!S) {
    immutable ubyte firstByte = readDataOrThrow!(ubyte)(stream);
    immutable bool finalFragment = (firstByte & 128) > 0;
    immutable bool reserved1 = (firstByte & 64) > 0;
    immutable bool reserved2 = (firstByte & 32) > 0;
    immutable bool reserved3 = (firstByte & 16) > 0;
    immutable ubyte opcode = firstByte & 15;
    if (reserved1 || reserved2 || reserved3) {
        throw new WebSocketException("Reserved header bits are set.");
    }
    if (!validateOpcode(opcode)) {
        import std.format : format;
        throw new WebSocketException(format!"Invalid opcode: %d"(opcode));
    }
    import std.typecons : tuple;
    return tuple!("finalFragment", "opcode")(finalFragment, opcode);
}

private bool validateOpcode(ubyte opcode) {
    import std.traits : EnumMembers;
    static foreach (member; EnumMembers!WebSocketFrameOpcode) {
        if (opcode == member) return true;
    }
    return false;
}

/**
 * Reads the payload length of a websocket frame, given an initial 7-bit length
 * value read from the second byte of the frame's header. This may throw a
 * websocket exception if the length format is invalid.
 * Params:
 *   initialLength = The initial 7-bit length value.
 *   stream = The stream to read from.
 * Returns: The complete payload length.
 */
private ulong readPayloadLength(S)(ubyte initialLength, S stream) if (isByteInputStream!S) {
    if (initialLength == 126) {
        return readDataOrThrow!(ushort)(stream);
    } else if (initialLength == 127) {
        return readDataOrThrow!(ulong)(stream);
    }
    return initialLength;
}

/**
 * Reads the payload of a websocket frame, or throws a websocket exception if
 * the payload can't be read in its entirety.
 * Params:
 *   payloadLength = The length of the payload.
 *   stream = The stream to read from.
 * Returns: The payload data that was read.
 */
private ubyte[] readPayload(S)(ulong payloadLength, S stream) if (isByteInputStream!S) {
    ubyte[] buffer = new ubyte[payloadLength];
    StreamResult readResult = stream.readFromStream(buffer);
    if (readResult.hasError) {
        throw new WebSocketException(cast(string) readResult.error.message);
    } else if (readResult.count != payloadLength) {
        import std.format : format;
        throw new WebSocketException(format!"Read %d bytes instead of expected %d for message payload."(
            readResult.count, payloadLength
        ));
    }
    return buffer;
}

/**
 * Helper function to read data from a byte stream, or throw a websocket
 * exception if reading fails for any reason.
 * Params:
 *   stream = The stream to read from.
 * Returns: The value that was read.
 */
private T readDataOrThrow(T, S)(S stream) if (isByteInputStream!S) {
    auto dIn = dataInputStreamFor(stream, Endianness.BigEndian);
    DataReadResult!T result = dIn.readFromStream!T();
    if (result.hasError) {
        throw new WebSocketException(cast(string) result.error.message);
    }
    return result.value;
}

private void writeDataOrThrow(T, S)(S stream, T data) if (isByteOutputStream!S) {
    auto dOut = dataOutputStreamFor(stream, Endianness.BigEndian);
    OptionalStreamError err = dOut.writeToStream(data);
    if (err.present) {
        throw new WebSocketException(cast(string) err.value.message);
    }
}

/**
 * Applies a 4-byte mask to a websocket frame's payload bytes.
 * Params:
 *   buffer = The buffer containing the payload.
 *   mask = The mask to apply.
 */
private void unmaskData(ubyte[] buffer, ubyte[4] mask) {
    for (size_t i = 0; i < buffer.length; i++) {
        buffer[i] = buffer[i] ^ mask[i % 4];
    }
}