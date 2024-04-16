module handy_httpd.components.socket_range;

import std.socket;
import slf4d;

struct SocketOutputRange {
    private Socket socket;

    void put(ubyte[] data) {
        infoF!"Sending data to socket:\n%s"(cast(string) data);
        ptrdiff_t sent = socket.send(data);
        infoF!"  Sent %d bytes."(sent);
        if (sent != data.length) throw new Exception("Couldn't send all data.");
    }
}

struct SocketInputRange {
    private Socket socket;
    private ubyte[] buffer;
    private size_t bytesAvailable;
    bool closed = false;

    this(Socket socket, ubyte[] buffer) {
        this.socket = socket;
        this.buffer = buffer;
        this.closed = false;
        this.popFront();
    }

    bool empty() {
        return socket is null || closed || !socket.isAlive;
    }

    ubyte[] front() {
        return buffer[0 .. bytesAvailable];
    }

    void popFront() {
        if (closed || socket is null) return;
        ptrdiff_t readCount = socket.receive(buffer);
        if (readCount == 0 || readCount == Socket.ERROR) {
            closed = true;
        } else {
            bytesAvailable = readCount;
        }
    }
}