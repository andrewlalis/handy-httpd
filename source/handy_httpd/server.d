module handy_httpd.server;

import std.stdio;
import std.socket;
import std.regex;
import std.uri;

import handy_httpd.request;
import handy_httpd.response;

class HttpServer {
    private Address address;
    private ubyte[] receiveBuffer;
    public shared bool verbose;
    private HttpRequestHandler handler;

    this(
        HttpRequestHandler handler,
        string hostname = "127.0.0.1",
        ushort port = 8080,
        size_t receiveBufferSize = 8192,
        bool verbose = true
    ) {
        this.address = parseAddress(hostname, port);
        this.receiveBuffer = new ubyte[receiveBufferSize];
        this.verbose = verbose;
        this.handler = handler;
    }

    this(
        HttpResponse function(HttpRequest) handlerFunction,
        string hostname = "127.0.0.1",
        ushort port = 8080,
        size_t receiveBufferSize = 8192,
        bool verbose = true
    ) {
        this(simpleHandler(handlerFunction), hostname, port, receiveBufferSize, verbose);
    }

    public void start() {
        auto serverSocket = new TcpSocket();
        serverSocket.bind(address);
        if (verbose) writefln("Bound to address %s", address);
        serverSocket.listen(5);
        if (verbose) writeln("Now accepting connections.");
        while (serverSocket.isAlive()) {
            auto clientSocket = serverSocket.accept();
            auto received = clientSocket.receive(this.receiveBuffer);
            if (verbose) writefln!"Received request from %s with size of %d bytes."(clientSocket.remoteAddress, received);
            auto request = parseRequest(cast(string) receiveBuffer[0..received]);
            clientSocket.send(handler.handle(request).toBytes());
            clientSocket.close();
        }
    }

    private HttpRequest parseRequest(string s) {
        auto r = ctRegex!(`(\S+)`);
        auto rm = matchAll(s, r);
        string method = rm.front.hit;
        rm.popFront();
        string url = decode(rm.front.hit);
        rm.popFront();
        string httpVersion = rm.front.hit;
        rm.popFront();
        HttpRequest request = HttpRequest(method, url, httpVersion);
        return request;
    }
}

interface HttpRequestHandler {
    HttpResponse handle(HttpRequest request);
}

HttpRequestHandler simpleHandler(HttpResponse function(HttpRequest) fn) {
    return new class HttpRequestHandler {
        HttpResponse handle(HttpRequest request) {
            return fn(request);
        }
    };
}
