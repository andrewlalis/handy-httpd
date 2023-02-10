module handy_httpd.util.range;

import std.socket;
import std.range.interfaces : InputRange, OutputRange, UnsupportedRangeMethod;

/** 
 * Helper static function to check if a type is an input range that supplies
 * elements of the given type `E`.
 */
template isInputRangeOf(R, E) {
    import std.range.primitives: isInputRange, ElementType;
    enum isInputRangeOf = isInputRange!R && is(ElementType!R == E);
}

/** 
 * An input range that reads chunks of `ubyte[]` from a Socket until all data
 * has been read. It offers support for an initial buffer offset and received
 * count, which is needed to pick up reading immediately after consuming an
 * HTTP request header.
 */
class SocketInputRange : InputRange!(ubyte[]) {
    private Socket socket;
    private ubyte[]* receiveBuffer;
    private size_t bufferOffset;
    private size_t receivedCount;
    private bool inputEnded = false;

    public this(Socket socket, ubyte[]* receiveBuffer, size_t initialBufferOffset, size_t initialReceivedCount) {
        this.socket = socket;
        this.receiveBuffer = receiveBuffer;
        this.bufferOffset = initialBufferOffset;
        this.receivedCount = initialReceivedCount;
    }

    public ubyte[] front() {
        return (*receiveBuffer)[bufferOffset .. receivedCount];
    }

    public void popFront() {
        bufferOffset = 0;
        receivedCount = socket.receive(*receiveBuffer);
        if (receivedCount == Socket.ERROR) {
            import std.string : format;
            string msg = format!"Error while receiving data. Received %d."(receivedCount);
            throw new SocketException(msg);
        } else if (receivedCount == 0) {
            inputEnded = true;
        }
    }

    public bool empty() {
        return !inputEnded;
    }

    public ubyte[] moveFront() {
        ubyte[] data = this.front();
        this.popFront();
        return data;
    }

    public int opApply(scope int delegate(ubyte[]) dg) {
        throw new UnsupportedRangeMethod("Not implemented.");
    }

    public int opApply(scope int delegate(size_t, ubyte[]) dg) {
        throw new UnsupportedRangeMethod("Not implemented.");
    }
}

unittest {
    import std.range;
    assert(isInputRangeOf!(SocketInputRange, ubyte[]));
}

/** 
 * An output range that writes chunks of `ubyte[]` to a Socket.
 */
class SocketOutputRange : OutputRange!(ubyte[]) {
    private Socket socket;

    public this(Socket socket) {
        this.socket = socket;
    }

    public void put(ubyte[] data) {
        size_t bytesSent = socket.send(data);
        if (bytesSent == Socket.ERROR || bytesSent != data.length) {
            import std.string : format;
            string msg = format!"Error while sending data. Expected to send %d bytes, but only sent %d."(data.length, bytesSent);
            throw new SocketException(msg);
        }
    }
}

unittest {
    import std.range;
    assert(isOutputRange!(SocketOutputRange, ubyte[]));
}

/** 
 * A simple output range implementation that just discards anything that was
 * written to it. Useful for testing.
 */
class DiscardingOutputRange : OutputRange!(ubyte[]) {
    public void put(ubyte[] data) {
        // Do nothing with the data.
    }
}
