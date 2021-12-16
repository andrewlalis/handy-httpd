module handy_httpd.server;

import std.stdio;
import std.socket;
import std.regex;
import std.uri;
import httparsed;

import handy_httpd.request;
import handy_httpd.response;

struct Header {
    const(char)[] name;
    const(char)[] value;
}

struct Msg {
    @safe pure nothrow @nogc:
        void onMethod(const(char)[] method) { this.method = method; }

        void onUri(const(char)[] uri) { this.uri = uri; }

        int onVersion(const(char)[] ver) {
            minorVer = parseHttpVersion(ver);
            return minorVer >= 0 ? 0 : minorVer;
        }

        void onHeader(const(char)[] name, const(char)[] value) {
            this.m_headers[m_headersLength].name = name;
            this.m_headers[m_headersLength++].value = value;
        }

        void onStatus(int status) { this.status = status; }

        void onStatusMsg(const(char)[] statusMsg) { this.statusMsg = statusMsg; }

    public const(char)[] method;
    public const(char)[] uri;
    public int minorVer;
    public int status;
    public const(char)[] statusMsg;

    private Header[64] m_headers;
    private size_t m_headersLength;

    Header[] headers() return { return m_headers[0..m_headersLength]; }
}

class HttpServer {
    private Address address;
    size_t receiveBufferSize;
    private MsgParser!Msg requestParser;
    private bool verbose;
    private HttpRequestHandler handler;

    this(
        HttpRequestHandler handler,
        string hostname = "127.0.0.1",
        ushort port = 8080,
        size_t receiveBufferSize = 8192,
        bool verbose = false
    ) {
        this.address = parseAddress(hostname, port);
        this.receiveBufferSize = receiveBufferSize;
        this.verbose = verbose;
        this.handler = handler;
        this.requestParser = initParser!Msg();
    }

    this(
        HttpResponse function(HttpRequest) handlerFunction,
        string hostname = "127.0.0.1",
        ushort port = 8080,
        size_t receiveBufferSize = 8192,
        bool verbose = false
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
            handleRequest(clientSocket);
        }
    }

    private void handleRequest(Socket clientSocket) {
        ubyte[] receiveBuffer = new ubyte[receiveBufferSize];
        auto received = clientSocket.receive(receiveBuffer);
        string data = cast(string) receiveBuffer[0..received];
        auto request = parseRequest(data);
        if (verbose) writefln!"<- %s %s"(request.method, request.url);
        auto response = handler.handle(request);
        if (verbose) writefln!"-> %s %s"(response.status, response.statusText);
        clientSocket.send(response.toBytes());
        clientSocket.close();
    }

    private HttpRequest parseRequest(string s) {
        requestParser.msg.m_headersLength = 0; // Reset the parser headers.
        int result = requestParser.parseRequest(s);
        if (result != s.length) {
            throw new Exception("Error! parse result doesn't match length.");
        }
        string[string] headers;
        foreach (h; requestParser.headers) {
            headers[h.name] = cast(string) h.value;
        }
        HttpRequest request = HttpRequest(
            cast(string) requestParser.method,
            decode(cast(string) requestParser.uri),
            requestParser.minorVer,
            headers
        );
        return request;
    }

    /** 
     * Sets the server's verbosity.
     * Params:
     *   verbose = Whether to enable verbose output.
     * Returns: The server instance, for method chaining.
     */
    public HttpServer setVerbose(bool verbose) {
        this.verbose = verbose;
        return this;
    }
}

/** 
 * Interface for any component that handles HTTP requests.
 */
interface HttpRequestHandler {
    /** 
     * Handles an HTTP request.
     * Params:
     *   request = The request to handle.
     * Returns: An HTTP response to send to the client.
     */
    HttpResponse handle(HttpRequest request);
}

/** 
 * Helper method to produce an HttpRequestHandler from a function.
 * Params:
 *   fn = The function that will handle requests.
 * Returns: The request handler.
 */
HttpRequestHandler simpleHandler(HttpResponse function(HttpRequest) fn) {
    return new class HttpRequestHandler {
        HttpResponse handle(HttpRequest request) {
            return fn(request);
        }
    };
}
