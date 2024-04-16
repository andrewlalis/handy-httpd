/**
 * Internal parsing utilities for the server's HTTP request processing.
 */
module handy_httpd.components.parse_utils;

import handy_httpd.server : HttpServer;

import std.typecons;
import std.conv;
import std.array;
import std.string;
import std.algorithm;
import std.uri;
import std.range;
import std.socket : Socket, Address, lastSocketError;
import slf4d : Logger, getLogger;
import http_primitives;
import httparsed;

/**
 * The header struct to use when parsing data.
 */
public struct Header {
    const(char)[] name;
    const(char)[] value;
}

/**
 * The message struct to use when parsing HTTP requests, using the httparsed library.
 */
public struct Msg {
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

        void reset() {
            this.m_headersLength = 0;
        }

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
 * Parses an HTTP request from a string.
 * Params:
 *   s = The raw HTTP request string.
 * Returns: A tuple containing the http request and the size of data read.
 */
public Tuple!(HttpRequest, int) parseRequest(ref MsgParser!Msg requestParser, string s) {
    int result = requestParser.parseRequest(s);
    if (result < 1) {
        throw new Exception("Couldn't parse header.");
    }
    
    StringMultiValueMap.Builder headersBuilder;
    foreach (h; requestParser.headers) {
        headersBuilder.add(cast(string) h.name, cast(string) h.value);
    }
    string rawUrl = decode(cast(string) requestParser.uri);
    Tuple!(string, StringMultiValueMap) urlAndParams = parseUrlAndParams(rawUrl);
    string method = cast(string) requestParser.method;
    HttpRequest request = HttpRequest(
        methodFromName(method).orElseThrow("Invalid HTTP method verb: " ~ method),
        urlAndParams[0],
        cast(ubyte) requestParser.minorVer,
        headersBuilder.build(),
        urlAndParams[1],
        null
    );
    return tuple(request, result);
}

/**
 * Parses a path and set of query parameters from a raw URL string.
 * Params:
 *   rawUrl = The raw url containing both path and query params.
 * Returns: A tuple containing the path and parsed query params.
 */
public Tuple!(string, StringMultiValueMap) parseUrlAndParams(string rawUrl) {
    Tuple!(string, StringMultiValueMap) result;
    auto p = rawUrl.indexOf('?');
    if (p == -1) {
        result[0] = rawUrl;
    } else {
        result[0] = rawUrl[0..p];
        result[1] = parseFormUrlEncoded(rawUrl[p..$], false);
    }
    // Strip away a trailing slash if there is one. This makes path matching easier.
    if (result[0][$ - 1] == '/') {
        result[0] = result[0][0 .. $ - 1];
    }
    return result;
}

/**
 * Attempts to receive an HTTP request from the given socket.
 * Params:
 *   server = The server that accepted the client socket.
 *   clientSocket = The underlying socket to the client.
 *   inputStream = The input stream to use.
 *   outputStream = The output stream to use.
 *   receiveBuffer = The raw buffer that is used to store data that was read.
 *   requestParser = The HTTP request parser.
 *   logger = A logger to use to write log messages.
 * Returns: An optional request context. If null, then the client socket can
 * be closed and no further action is required. Otherwise, it is a valid
 * request context that can be handled using the server's configured handler.
 */
public Optional!(Tuple!(HttpRequest, HttpResponse)) receiveRequest(I, O)(
    HttpServer server,
    Socket clientSocket,
    I inputRange,
    O outputRange,
    ubyte[] receiveBuffer,
    ref MsgParser!Msg requestParser,
    Logger logger = getLogger()
) if (isInputRange!(I) && is(ElementType!(I) == ubyte[]) && isOutputRange!(O, ubyte[])) {
    alias ResultType = Optional!(Tuple!(HttpRequest, HttpResponse));
    // First try and read as much as we can from the input stream into the buffer.
    logger.trace("Reading the initial request into the receive buffer.");
    if (inputRange.empty) return ResultType.empty;
    ubyte[] initialReadData = inputRange.front();

    logger.debugF!"Received %d bytes from the client.\n%s\n"(initialReadData.length, cast(string) initialReadData);
    if (initialReadData.length == 0) return ResultType.empty; // Skip if we didn't receive valid data.

    // We store an immutable copy of the data initially received, so we can
    // slice it and work with it even as we keep reading and overwriting the
    // receive buffer.
    immutable ubyte[] initialData = initialReadData.idup;

    // Prepare the request context by parsing the HttpRequest, and preparing the context.
    try {
        auto requestAndSize = parseRequest(requestParser, cast(string) initialData);
        HttpRequest request = requestAndSize[0];
        logger.debugF!"Parsed first %d bytes as the HTTP request."(requestAndSize[1]);
        
        // We got a valid request, so prepare the context.

        const int bytesReceived = cast(int) initialReadData.length;
        const int bytesRead = requestAndSize[1];
        if (bytesReceived > bytesRead) {
            request.inputRange = chain([receiveBuffer[bytesRead .. bytesReceived]], inputRange).inputRangeObject;
        } else {
            request.inputRange = new InputRangeObject!(typeof(inputRange))(inputRange);
        }
        request.remoteAddress = clientSocket.remoteAddress;
        
        HttpResponse response;
        response.outputRange = new OutputRangeObject!(typeof(outputRange), ubyte[])(outputRange);
        response.headers.add("Connection", "close");
        foreach (header, value; server.config.defaultHeaders) {
            response.headers.add(header, value);
        }
        return ResultType.of(tuple(request, response));
    } catch (Exception e) {
        logger.warnF!"Failed to parse HTTP request: %s"(e.msg);
        return ResultType.empty;
    }
}
