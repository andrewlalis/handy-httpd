/** 
 * Contains HTTP response components.
 */
module handy_httpd.components.response;

import handy_httpd.util.range;

import std.array;
import std.string : format, representation;
import std.conv;
import std.socket : Socket;
import std.range;
import slf4d;

/** 
 * The data that the HTTP server will send back to clients.
 */
struct HttpResponse {
    /** 
     * The response status.
     */
    public StatusInfo status = HttpStatus.OK;

    /** 
     * An associative array of headers.
     */
    public string[string] headers;

    /** 
     * Internal flag used to determine if we've already flushed the headers.
     */
    private bool flushed = false;

    /** 
     * The output range that the response body will be written to. In practice
     * this will usually be a `SocketOutputRange`.
     */
    public OutputRange!(ubyte[]) outputRange;

    /** 
     * Sets the status of the response. This can only be done before headers
     * are flushed.
     * Params:
     *   newStatus = The status to set.
     * Returns: The response object, for method chaining.
     */
    public HttpResponse setStatus(HttpStatus newStatus) {
        if (flushed) {
            warnF!"Attempted to set status to %s after the response has already been flushed."(newStatus);
        }
        this.status = newStatus;
        return this;
    }

    /** 
     * Adds a header to the response. This can only be done before headers are
     * flushed.
     * Params:
     *   name = The name of the header.
     *   value = The value to set for the header.
     * Returns: The response object, for method chaining.
     */
    public HttpResponse addHeader(string name, string value) {
        if (flushed) {
            warnF!"Attempted to set header \"%s\" to \"%s\" after the response has already been flushed."(name, value);
        }
        this.headers[name] = value;
        return this;
    }

    /** 
     * Flushes the headers for this request. Once this is done, header
     * information can no longer be modified.
     */
    public void flushHeaders() {
        if (flushed) {
            warn("Attempted to flush headers after the response has already been flushed.");
        }
        auto app = appender!string;
        app ~= format!"HTTP/1.1 %d %s\r\n"(this.status.code, this.status.text);
        foreach (name, value; this.headers) {
            app ~= format!"%s: %s\r\n"(name, value);
        }
        app ~= "\r\n";
        this.outputRange.put(cast(ubyte[]) app[]);
        flushed = true;
    }

    /** 
     * Writes the body of the response using data obtained from the given
     * input range. Note that it is required to specify the size of the data
     * to write beforehand, since we should always send a Content-Length header
     * to the client.
     * Params:
     *   inputRange = The input range to send data from.
     *   size = The pre-computed size of the content.
     *   contentType = The content type of the response.
     */
    public void writeBodyRange(R)(R inputRange, ulong size, string contentType) if (isInputRangeOf!(R, ubyte[])) {
        if (!flushed) {
            addHeader("Content-Length", size.to!string);
            addHeader("Content-Type", contentType);
            flushHeaders();
        }
        ulong bytesWritten = 0;
        while (!inputRange.empty) {
            ulong bytesToWrite = size - bytesWritten;
            ubyte[] data = inputRange.front();
            // We can safely cast the length to an integer, since it is a buffer size.
            uint idx = cast(uint) data.length;
            if (idx > bytesToWrite) {
                idx = cast(uint) bytesToWrite; // This is safe since we know that bytesToWrite is small.
            }
            this.outputRange.put(data[0 .. idx]);
            bytesWritten += idx;
            inputRange.popFront();
        }
    }

    /** 
     * Writes the given byte content to the body of the response. If this
     * response has not yet written its status line and headers, it will do
     * that first.
     * Params:
     *   data = The data to write.
     *   contentType = The content type of the data.
     */
    public void writeBodyBytes(ubyte[] data, string contentType = "application/octet-stream") {
        this.writeBodyRange([data], data.length, contentType);
    }

    /** 
     * Writes the given text to the body of the response. It's a simple wrapper
     * around `writeBody(ubyte[], string)`.
     * Params:
     *   text = The text to write.
     *   contentType = The content type of the text. Defaults to text/plain.
     */
    public void writeBodyString(string text, string contentType = "text/plain; charset=utf-8") {
        writeBodyBytes(cast(ubyte[]) text, contentType);
    }

    /** 
     * Tells whether the header of this response has already been flushed.
     * Returns: Whether the response headers have been flushed.
     */
    public bool isFlushed() {
        return flushed;
    }
}

/** 
 * A struct containing basic information about a response status.
 */
struct StatusInfo {
    ushort code;
    string text;
}

/** 
 * An enum defining all valid HTTP response statuses:
 * See here: https://developer.mozilla.org/en-US/docs/Web/HTTP/Status
 */
enum HttpStatus : StatusInfo {
    // Information
    CONTINUE = StatusInfo(100, "Continue"),
    SWITCHING_PROTOCOLS = StatusInfo(101, "Switching Protocols"),
    PROCESSING = StatusInfo(102, "Processing"),
    EARLY_HINTS = StatusInfo(103, "Early Hints"),

    // Success
    OK = StatusInfo(200, "OK"),
    CREATED = StatusInfo(201, "Created"),
    ACCEPTED = StatusInfo(202, "Accepted"),
    NON_AUTHORITATIVE_INFORMATION = StatusInfo(203, "Non-Authoritative Information"),
    NO_CONTENT = StatusInfo(204, "No Content"),
    RESET_CONTENT = StatusInfo(205, "Reset Content"),
    PARTIAL_CONTENT = StatusInfo(206, "Partial Content"),
    MULTI_STATUS = StatusInfo(207, "Multi-Status"),
    ALREADY_REPORTED = StatusInfo(208, "Already Reported"),
    IM_USED = StatusInfo(226, "IM Used"),

    // Redirection
    MULTIPLE_CHOICES = StatusInfo(300, "Multiple Choices"),
    MOVED_PERMANENTLY = StatusInfo(301, "Moved Permanently"),
    FOUND = StatusInfo(302, "Found"),
    SEE_OTHER = StatusInfo(303, "See Other"),
    NOT_MODIFIED = StatusInfo(304, "Not Modified"),
    TEMPORARY_REDIRECT = StatusInfo(307, "Temporary Redirect"),
    PERMANENT_REDIRECT = StatusInfo(308, "Permanent Redirect"),

    // Client error
    BAD_REQUEST = StatusInfo(400, "Bad Request"),
    UNAUTHORIZED = StatusInfo(401, "Unauthorized"),
    PAYMENT_REQUIRED = StatusInfo(402, "Payment Required"),
    FORBIDDEN = StatusInfo(403, "Forbidden"),
    NOT_FOUND = StatusInfo(404, "Not Found"),
    METHOD_NOT_ALLOWED = StatusInfo(405, "Method Not Allowed"),
    NOT_ACCEPTABLE = StatusInfo(406, "Not Acceptable"),
    PROXY_AUTHENTICATION_REQUIRED = StatusInfo(407, "Proxy Authentication Required"),
    REQUEST_TIMEOUT = StatusInfo(408, "Request Timeout"),
    CONFLICT = StatusInfo(409, "Conflict"),
    GONE = StatusInfo(410, "Gone"),
    LENGTH_REQUIRED = StatusInfo(411, "Length Required"),
    PRECONDITION_FAILED = StatusInfo(412, "Precondition Failed"),
    PAYLOAD_TOO_LARGE = StatusInfo(413, "Payload Too Large"),
    URI_TOO_LONG = StatusInfo(414, "URI Too Long"),
    UNSUPPORTED_MEDIA_TYPE = StatusInfo(415, "Unsupported Media Type"),
    RANGE_NOT_SATISFIABLE = StatusInfo(416, "Range Not Satisfiable"),
    EXPECTATION_FAILED = StatusInfo(417, "Expectation Failed"),
    IM_A_TEAPOT = StatusInfo(418, "I'm a teapot"),
    MISDIRECTED_REQUEST = StatusInfo(421, "Misdirected Request"),
    UNPROCESSABLE_CONTENT = StatusInfo(422, "Unprocessable Content"),
    LOCKED = StatusInfo(423, "Locked"),
    FAILED_DEPENDENCY = StatusInfo(424, "Failed Dependency"),
    TOO_EARLY = StatusInfo(425, "Too Early"),
    UPGRADE_REQUIRED = StatusInfo(426, "Upgrade Required"),
    PRECONDITION_REQUIRED = StatusInfo(428, "Precondition Required"),
    TOO_MANY_REQUESTS = StatusInfo(429, "Too Many Requests"),
    REQUEST_HEADER_FIELDS_TOO_LARGE = StatusInfo(431, "Request Header Fields Too Large"),
    UNAVAILABLE_FOR_LEGAL_REASONS = StatusInfo(451, "Unavailable For Legal Reasons"),

    // Server error
    INTERNAL_SERVER_ERROR = StatusInfo(500, "Internal Server Error"),
    NOT_IMPLEMENTED = StatusInfo(501, "Not Implemented"),
    BAD_GATEWAY = StatusInfo(502, "Bad Gateway"),
    SERVICE_UNAVAILABLE = StatusInfo(503, "Service Unavailable"),
    GATEWAY_TIMEOUT = StatusInfo(504, "Gateway Timeout"),
    HTTP_VERSION_NOT_SUPPORTED = StatusInfo(505, "HTTP Version Not Supported"),
    VARIANT_ALSO_NEGOTIATES = StatusInfo(506, "Variant Also Negotiates"),
    INSUFFICIENT_STORAGE = StatusInfo(507, "Insufficient Storage"),
    LOOP_DETECTED = StatusInfo(508, "Loop Detected"),
    NOT_EXTENDED = StatusInfo(510, "Not Extended"),
    NETWORK_AUTHENTICATION_REQUIRED = StatusInfo(511, "Network Authentication Required")
}
