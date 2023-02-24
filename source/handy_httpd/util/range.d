/** 
 * This module contains some components that help in dealing with ranges,
 * especially with respect to request input and response output.
 * 
 * Of particular note is the `SocketInputRange` and `SocketOutputRange`. These
 * ranges are used in the normal implementation of Handy-Httpd when a request
 * context is initialized for a client.
 */
module handy_httpd.util.range;

import std.socket;
import std.range.interfaces : InputRange, OutputRange;
import slf4d;

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
 *
 * Note: This input range is **not** threadsafe.
 *
 * Calling `popFront()` may produce a `SocketException` if an error occurs
 * while receiving data from the socket.
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
        this.inputEnded = initialBufferOffset == initialReceivedCount && initialBufferOffset < receiveBuffer.length;
    }

    public ubyte[] front() {
        if (inputEnded) return [];
        return (*receiveBuffer)[bufferOffset .. receivedCount];
    }

    public void popFront() {
        auto log = getLogger();
        // If we've reached the end of input, quit.
        if (this.inputEnded) return;
        // If we initially received less data than could fit into the receive buffer,
        // then we know there's no more, so we can quit now.
        if (this.receivedCount < (*this.receiveBuffer).length) {
            this.inputEnded = true;
            return;
        }
        this.bufferOffset = 0;
        this.receivedCount = socket.receive(*this.receiveBuffer);
        log.debugF!"Received %d bytes from the socket."(this.receivedCount);
        if (this.receivedCount == Socket.ERROR) {
            import std.string : format;
            string msg = format!"Error while receiving data. Received %d."(this.receivedCount);
            throw new SocketException(msg);
        } else if (this.receivedCount == 0) {
            this.inputEnded = true;
        }
    }

    public bool empty() {
        return inputEnded;
    }

    public ubyte[] moveFront() {
        ubyte[] data = this.front();
        this.popFront();
        return data;
    }

    public int opApply(scope int delegate(ubyte[]) dg) {
        dg(front());
        popFront();
        return inputEnded ? 1 : 0;
    }

    public int opApply(scope int delegate(size_t, ubyte[]) dg) {
        ubyte[] data = front();
        dg(data.length, data);
        popFront();
        return inputEnded ? 1 : 0;
    }
}

unittest {
    import std.stdio;
    import std.range;
    assert(isInputRangeOf!(SocketInputRange, ubyte[]));

    Socket[2] sockets = socketPair();
    Socket inSocket = sockets[0];
    Socket outSocket = sockets[1];

    // outSocket.send([0, 1, 2, 3, 4, 5, 6, 7]);
    // outSocket.close();
    // ubyte[] buffer = new ubyte[8];
    // inSocket.receive(buffer);
    // // Construct an input range where we haven't read anything yet, and we received a full buffer.
    // SocketInputRange sir = new SocketInputRange(inSocket, &buffer, 0, buffer.length);
    // assert(!sir.empty);
    // assert(sir.front == [0, 1, 2, 3, 4, 5, 6, 7]);
    // sir.popFront();
    // assert(sir.empty);
}

/** 
 * A simple input range that is always empty. Useful for testing.
 */
class EmptyInputRange : InputRange!(ubyte[]) {
    public ubyte[] front() {
        return [];
    }

    public void popFront() {
        // Do nothing.
    }

    public bool empty() {
        return true;
    }

    public ubyte[] moveFront() {
        return [];
    }

    public int opApply(scope int delegate(ubyte[]) dg) {
        dg([]);
        return 1;
    }

    public int opApply(scope int delegate(size_t, ubyte[]) dg) {
        dg(0, []);
        return 1;
    }
}

/** 
 * An output range that writes chunks of `ubyte[]` to a Socket.
 *
 * Note that calling `put` may throw a `SocketException` if the given data
 * could not be written to the socket. For best performance, it's recommended
 * to write amounts of data in chunks.
 */
class SocketOutputRange : OutputRange!(ubyte[]) {
    private Socket socket;

    public this(Socket socket) {
        this.socket = socket;
    }

    public void put(ubyte[] data) {
        ptrdiff_t bytesSent = socket.send(data);
        if (bytesSent == Socket.ERROR || bytesSent != data.length) {
            import std.string : format;
            string errorText = lastSocketError();
            string msg = format!
                "Error while sending data. Expected to send %d bytes, but only sent %d. Last socket error: %s"
                (data.length, bytesSent, errorText);
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
