module handy_httpd.server;

import std.stdio;
import std.socket;
import std.regex;
import std.uri;
import std.conv;
import std.parallelism;
import std.string;
import std.typecons;
import std.array;
import std.algorithm;

import httparsed;

import handy_httpd.request;
import handy_httpd.response;
import handy_httpd.handler;

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

/** 
 * A simple HTTP server that accepts requests on a given port and address, and
 * lets a configured HttpRequestHandler produce a response, to send back to the
 * client.
 */
class HttpServer {
    private Address address;
    size_t receiveBufferSize;
    private MsgParser!Msg requestParser;
    private bool verbose;
    private HttpRequestHandler handler;
    private TaskPool workerPool;
    private bool ready = false;
    private Socket serverSocket = null;

    this(
        HttpRequestHandler handler = noOpHandler(),
        string hostname = "127.0.0.1",
        ushort port = 8080,
        size_t receiveBufferSize = 8192,
        bool verbose = false,
        size_t workerPoolSize = 25
    ) {
        this.address = parseAddress(hostname, port);
        this.receiveBufferSize = receiveBufferSize;
        this.verbose = verbose;
        this.handler = handler;
        this.requestParser = initParser!Msg();
        
        this.workerPool = new TaskPool(workerPoolSize);
        this.workerPool.isDaemon = true;
    }

    /** 
     * Starts the server on the calling thread, so that it will begin accepting
     * HTTP requests.
     */
    public void start() {
        serverSocket = new TcpSocket();
        serverSocket.bind(address);
        if (verbose) writefln("Bound to address %s", address);
        serverSocket.listen(100);
        if (verbose) writeln("Now accepting connections.");
        ready = true;
        while (serverSocket.isAlive()) {
            auto clientSocket = serverSocket.accept();
            auto t = task!handleRequest(clientSocket, handler, receiveBufferSize, verbose);
            workerPool.put(t);
        }
        ready = false;
    }

    /** 
     * Shuts down the server by closing the server socket, if possible. Note
     * that this is not a blocking call, and the server will shutdown soon.
     */
    public void stop() {
        if (serverSocket !is null) {
            serverSocket.close();
        }
    }

    public bool isReady() {
        return ready;
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

private void handleRequest(Socket clientSocket, HttpRequestHandler handler, size_t bufferSize, bool verbose) {
    ubyte[] receiveBuffer = new ubyte[bufferSize];
    auto received = clientSocket.receive(receiveBuffer);
    string data = cast(string) receiveBuffer[0..received];
    auto request = parseRequest(data);
    if (verbose) writefln!"<- %s %s"(request.method, request.url);
    try {
        auto response = handler.handle(request);
        clientSocket.send(response.toBytes());
        if (verbose) writefln!"\t-> %d %s"(response.status, response.statusText);
    } catch (Exception e) {
        writefln!"An error occurred while handling a request: %s"(e.msg);
    }
    clientSocket.close();
}

private HttpRequest parseRequest(string s) {
    MsgParser!Msg requestParser = initParser!Msg();
    // requestParser.msg.m_headersLength = 0; // Reset the parser headers.
    int result = requestParser.parseRequest(s);
    if (result != s.length) {
        throw new Exception("Error! parse result doesn't match length. " ~ result.to!string);
    }
    string[string] headers;
    foreach (h; requestParser.headers) {
        headers[h.name] = cast(string) h.value;
    }
    string rawUrl = decode(cast(string) requestParser.uri);
    auto urlAndParams = parseUrlAndParams(rawUrl);

    return HttpRequest(
        cast(string) requestParser.method,
        urlAndParams[0],
        requestParser.minorVer,
        headers,
        urlAndParams[1]
    );
}

/** 
 * Parses a path and set of query parameters from a raw URL string.
 * Params:
 *   rawUrl = The raw url containing both path and query params.
 * Returns: A tuple containing the path and parsed query params.
 */
private Tuple!(string, string[string]) parseUrlAndParams(string rawUrl) {
    Tuple!(string, string[string]) result;
    auto p = rawUrl.indexOf('?');
    if (p == -1) {
        result[0] = rawUrl;
        result[1] = null;
    } else {
        result[0] = rawUrl[0..p];
        result[1] = parseQueryString(rawUrl[p..$]);
    }
    return result;
}

/** 
 * Parses a set of query parameters from a query string.
 * Params:
 *   queryString = The raw query string to parse, including the preceding '?' character.
 * Returns: An associative array containing parsed params.
 */
private string[string] parseQueryString(string queryString) {
    string[string] params;
    if (queryString.length > 1) {
        string[] paramSections = queryString[1..$].split("&").filter!(s => s.length > 0).array;
        foreach (paramSection; paramSections) {
            string paramName;
            string paramValue;
            auto p = paramSection.indexOf('=');
            if (p == -1 || p + 1 == paramSection.length) {
                paramName = paramSection;
                paramValue = "true";
            } else {
                paramName = paramSection[0..p];
                paramValue = paramSection[p+1..$];
            }
            params[paramName] = paramValue;
        }
    }
    writeln(params);
    return params;
}
