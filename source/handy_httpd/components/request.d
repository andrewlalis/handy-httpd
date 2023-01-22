/** 
 * Contains HTTP request components.
 */
module handy_httpd.components.request;

import handy_httpd.server: HttpServer;
import handy_httpd.components.response : HttpResponse;
import std.socket : Socket;
import std.range;

/** 
 * The data which the server provides to HttpRequestHandlers so that they can
 * formulate a response.
 */
struct HttpRequest {
    /** 
     * The HTTP method verb, such as GET, POST, PUT, etc.
     */
    public const string method;

    /** 
     * The url of the request, excluding query parameters.
     */
    public const string url;

    /** 
     * The request version.
     */
    public const int ver;

    /** 
     * An associative array containing all request headers.
     */
    public const string[string] headers;

    /** 
     * An associative array containing all request params, if any were given.
     */
    public const string[string] params;

    /** 
     * An associative array containing any path parameters obtained from the
     * request url. These are only populated in cases where it is possible to
     * parse path parameters, such as with a PathDelegatingHandler.
     */
    public string[string] pathParams;

    /** 
     * A reference to the socket that's used to read this request.
     */
    public Socket clientSocket;

    /** 
     * A pointer to the internal receive buffer that the request was read from.
     */
    public ubyte[]* receiveBuffer;

    /** 
     * The offset in the receive buffer, that points to the start of the body
     * of the request, or is equal to the receivedByteCount if there is no body.
     */
    public size_t receiveBufferOffset;

    /** 
     * The number of bytes that were received into the receive buffer.
     */
    public size_t receivedByteCount;

    /** 
     * Gets a URL parameter as the specified type, or returns the default value
     * if the parameter with the given name doesn't exist.
     * Params:
     *   name = The name of the URL parameter.
     *   defaultValue = The default value to return if the URL parameter
     *                  doesn't exist.
     * Returns: The value of the URL parameter.
     */
    public T getParamAs(T)(string name, T defaultValue = T.init) {
        import std.conv : to;
        if (name !in params) return defaultValue;
        return params[name].to!T;
    }

    unittest {
        HttpRequest req = HttpRequest(
            "GET",
            "/api",
            1,
            string[string].init,
            [
                "a": "123",
                "b": "c",
                "c": "true"
            ],
            string[string].init
        );
        assert(req.getParamAs!int("a") == 123);
        assert(req.getParamAs!char("b") == 'c');
        assert(req.getParamAs!bool("c") == true);
        assert(req.getParamAs!int("d") == 0);
    }

    /** 
     * Gets a path parameter as the specified type, or returns the default
     * value if the path parameter with the given name doesn't exist.
     * Params:
     *   name = The name of the path parameter.
     *   defaultValue = The default value to return if the path parameter
     *                  doesn't exist.
     * Returns: The value of the path parameter.
     */
    public T getPathParamAs(T)(string name, T defaultValue = T.init) {
        import std.conv : to;
        if (name !in pathParams) return defaultValue;
        return pathParams[name].to!T;
    }

    unittest {
        HttpRequest req;
        req.pathParams = [
            "a": "123",
            "b": "c",
            "c": "true"
        ];
        assert(req.getPathParamAs!int("a") == 123);
        assert(req.getPathParamAs!char("b") == 'c');
        assert(req.getPathParamAs!bool("c") == true);
        assert(req.getPathParamAs!int("d") == 0);
    }

    /** 
     * Determines if this request has a body that can be read.
     * Returns: True if the request has a body, or false otherwise.
     */
    public bool hasBody() {
        return receivedByteCount > receiveBufferOffset;
    }

    /** 
     * Gets the start of the request body. This is the part of the body which
     * was present in the initial socket receive call. If the received byte
     * count is greater than or equal to the receive buffer size, then you
     * should continue reading from the socket with additional receive calls.
     * 
     * In that case, it is safe to continue using the receive buffer to receive
     * additional data from the socket.
     *
     * Returns: The bytes that contain the start of the request body.
     */
    public ubyte[] getStartOfBody() {
        return (*receiveBuffer)[receiveBufferOffset .. receivedByteCount];
    }

    /** 
     * Reads the entirety of the request body, and passes it in chunks to the
     * given output range. This will use the request's client socket to keep
     * receiving chunks of data using the worker's receive buffer, until we've
     * read the whole body.
     * Params:
     *   outputRange = The output range to use.
     */
    public void readBody(R)(R outputRange) if (isOutputRange!(R, ubyte[])) {
        import std.conv : to;
        // If the request didn't specify content-length, stay safe and only
        // output what we've already read.
        if ("Content-Length" !in headers) {
            outputRange.put(getStartOfBody());
            return;
        }
        ulong contentLength = headers["Content-Length"].to!ulong;
        long bytesToRead = contentLength;
        ubyte[] start = getStartOfBody();
        outputRange.put(start);
        bytesToRead -= start.length;
        // If we weren't able to read the entire body in just the start.
        if (bytesToRead > 0) {
            while (bytesToRead > 0) {
                size_t received = clientSocket.receive(*receiveBuffer);
                if (received < 1) {
                    throw new Exception("Socket receive failed.");
                }
                size_t bufferEndIdx = received > bytesToRead ? bytesToRead : received;
                outputRange.put((*receiveBuffer)[0 .. bufferEndIdx]);
                bytesToRead -= received;
            }
        }
    }
}

/** 
 * A utility class for a fluent interface for building requests. This is useful
 * for testing.
 */
class HttpRequestBuilder {
    string method;
    string url;
    string[string] headers;
    string[string] params;
    string[string] pathParams;

    this(string method, string url) {
        this.method = method;
        this.url = url;
    }

    HttpRequestBuilder withHeader(string name, string value) {
        this.headers[name] = value;
        return this;
    }

    HttpRequestBuilder withParam(string name, string value) {
        this.params[name] = value;
        return this;
    }

    HttpRequestBuilder withPathParam(string name, string value) {
        this.pathParams[name] = value;
        return this;
    }

    HttpRequest build() {
        return HttpRequest(
            this.method,
            this.url,
            1,
            this.headers,
            this.params,
            this.pathParams
        );
    }
}
