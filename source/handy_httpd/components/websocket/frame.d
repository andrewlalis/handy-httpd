/**
 * Contains the low-level implementation of the WebSocket data frame spec,
 * as well as some friendly functions for reading and writing data frames
 * from D types.
 */
module handy_httpd.components.websocket.frame;

import handy_httpd.components.websocket.handler : WebSocketException;
import std.range;
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

void sendWebSocketTextFrame(O)(O outputRange, string text) if (isOutputRange!(O, ubyte[])) {
    sendWebSocketFrame!O(
        outputRange,
        WebSocketFrame(true, WebSocketFrameOpcode.TEXT_FRAME, cast(ubyte[]) text)
    );
}

void sendWebSocketBinaryFrame(O)(O outputRange, ubyte[] bytes) if (isOutputRange!(O, ubyte[])) {
    sendWebSocketFrame!O(
        outputRange,
        WebSocketFrame(true, WebSocketFrameOpcode.BINARY_FRAME, bytes)
    );
}

void sendWebSocketCloseFrame(O)(O outputRange, WebSocketCloseStatusCode code, string message)
    if (isOutputRange!(O, ubyte[])
) {
    import std.array : Appender;
    import std.bitmanip : append;

    Appender!(ubyte[]) app;
    app.append!ushort(code);
    if (message !is null && message.length > 0) {
        if (message.length > 123) {
            throw new WebSocketException("Close message is too long! Maximum of 123 bytes allowed.");
        }
        app ~= cast(ubyte[]) message;
    }
    sendWebSocketFrame!O(
        outputRange,
        WebSocketFrame(true, WebSocketFrameOpcode.CONNECTION_CLOSE, app[])
    );
}

void sendWebSocketPingFrame(O)(O outputRange, ubyte[] payload) if (isOutputRange!(O, ubyte[])) {
    sendWebSocketFrame!O(
        outputRange,
        WebSocketFrame(true, WebSocketFrameOpcode.PING, payload)
    );
}

void sendWebSocketPongFrame(O)(O outputRange, ubyte[] pingPayload) if (isOutputRange!(O, ubyte[])) {
    sendWebSocketFrame!O(
        outputRange,
        WebSocketFrame(true, WebSocketFrameOpcode.PONG, pingPayload)
    );
}

/**
 * Sends a websocket frame to a byte output range.
 * Params:
 *   outputRange = The output range to write to.
 *   frame = The frame to write.
 */
void sendWebSocketFrame(O)(O outputRange, WebSocketFrame frame) if (isOutputRange!(O, ubyte[])) {
    import std.array : Appender;
    import std.bitmanip : append;

    Appender!(ubyte[]) app;
    ubyte finAndOpcode = frame.opcode;
    if (frame.finalFragment) {
        finAndOpcode |= 128;
    }
    app.append!ubyte(finAndOpcode);
    if (frame.payload.length < 126) {
        app.append!ubyte(cast(ubyte) frame.payload.length);
    } else if (frame.payload.length <= ushort.max) {
        app.append!ubyte(cast(ubyte) 126);
        app.append!ushort(cast(ushort) frame.payload.length);
    } else {
        app.append!ubyte(cast(ubyte) 127);
        app.append!ulong(cast(ulong) frame.payload.length);
    }
    app ~= frame.payload;
    outputRange.put(app[]);
}

/**
 * Receives a websocket frame from a byte input stream.
 * Params:
 *   inputRange = The input range to receive the frame from.
 * Returns: The frame that was received.
 */
WebSocketFrame receiveWebSocketFrame(I)(I inputRange)
    if (isInputRange!I && is(ElementType!I == ubyte)
) {
    import std.bitmanip : read;
    if (inputRange.empty) {
        throw new WebSocketException("Cannot read websocket frame because input range is empty.");
    }

    auto finalAndOpcode = parseFinAndOpcode(inputRange.front);
    inputRange.popFront;
    immutable bool finalFragment = finalAndOpcode.finalFragment;
    immutable ubyte opcode = finalAndOpcode.opcode;
    immutable bool isControlFrame = (
        opcode == WebSocketFrameOpcode.CONNECTION_CLOSE ||
        opcode == WebSocketFrameOpcode.PING ||
        opcode == WebSocketFrameOpcode.PONG
    );

    immutable ubyte maskAndLength = inputRange.front;
    inputRange.popFront;
    immutable bool payloadMasked = (maskAndLength & 128) > 0;
    immutable ubyte initialPayloadLength = maskAndLength & 127;
    size_t payloadLength;
    debugF!"Websocket data frame Mask bit = %s, Initial payload length = %d"(payloadMasked, initialPayloadLength);
    if (initialPayloadLength < 126) {
        payloadLength = initialPayloadLength;
    } else if (initialPayloadLength == 126) {
        payloadLength = read!ushort(inputRange);
    } else {
        payloadLength = read!ulong(inputRange);
    }
    if (isControlFrame && payloadLength > 125) {
        throw new WebSocketException("Control frame payload is too large (> 125 bytes).");
    }

    ubyte[4] maskingKey;
    if (payloadMasked) {
        maskingKey = read!(ubyte[4])(inputRange);
    }
    debugF!"Receiving websocket frame: (FIN=%s,OP=%d,MASK=%s,LENGTH=%d)"(
        finalFragment,
        opcode,
        payloadMasked,
        payloadLength
    );
    ubyte[] payloadBuffer = new ubyte[payloadLength];
    size_t payloadBufferIdx = 0;
    while (payloadBufferIdx < payloadLength && !inputRange.empty) {
        payloadBuffer[payloadBufferIdx++] = inputRange.front;
        inputRange.popFront;
    }
    if (payloadBufferIdx < payloadLength) throw new WebSocketException("Couldn't read entire frame payload.");
    
    if (payloadMasked) unmaskData(payloadBuffer, maskingKey);

    return WebSocketFrame(
        finalFragment,
        cast(WebSocketFrameOpcode) opcode,
        payloadBuffer
    );
}

/**
 * Parses the `finalFragment` flag and opcode from a websocket frame's first
 * header byte.
 * Params:
 *   firstByte = The first byte of data.
 * Returns: A tuple containing the "bool finalFragment" and "ubyte opcode" properties.
 */
private auto parseFinAndOpcode(const ubyte firstByte) {
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
 * Reads the payload of a websocket frame, or throws a websocket exception if
 * the payload can't be read in its entirety.
 * Params:
 *   payloadLength = The length of the payload.
 *   stream = The stream to read from.
 * Returns: The payload data that was read.
 */
private ubyte[] readPayload(S)(size_t payloadLength, S stream) if (isByteInputStream!S) {
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