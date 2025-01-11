/** 
 * Contains HTTP response components.
 */
module handy_httpd.components.response;

import handy_httpd.components.multivalue_map;

import std.array : appender;
import std.conv : to;
import std.socket : Socket;
import slf4d;
import streams;

/** 
 * The data that the HTTP server will send back to clients.
 */
struct HttpResponse {
    /** 
     * The response status.
     */
    public StatusInfo status = HttpStatus.OK;

    /** 
     * A multi-valued map of response headers.
     */
    public StringMultiValueMap headers;

    /** 
     * Internal flag used to determine if we've already flushed the headers.
     */
    private bool flushed = false;

    /** 
     * The output stream that the response body will be written to.
     */
    public OutputStream!ubyte outputStream;

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
        this.headers.add(name, value);
        return this;
    }

    /**
     * Makes the response's body use "chunked" transfer-encoding. See here for
     * more info: https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Transfer-Encoding
     * Only call this method if you have not flushed the response's headers yet
     * and you haven't written anything to the response body.
     * Returns: The response object, for method chaining.
     */
    public HttpResponse chunked() {
        if (flushed) {
            warn("Attempted to set response body as chunked-encoded after headers have been flushed.");
            return this;
        }
        this.addHeader("Transfer-Encoding", "chunked");
        this.outputStream = outputStreamObjectFor(ChunkedEncodingOutputStream!(OutputStream!ubyte)(this.outputStream));
        return this;
    }

    /** 
     * Flushes the headers for this request. Once this is done, header
     * information can no longer be modified.
     */
    public void flushHeaders() {
        debug_("Flushing response headers.");
        if (flushed) {
            warn("Attempted to flush headers after the response has already been flushed.");
        }
        auto app = appender!string;
        app ~= "HTTP/1.1 " ~ to!string(this.status.code) ~ " " ~ this.status.text ~ "\r\n";
        foreach (name, value; this.headers) {
            app ~= name ~ ": " ~ value ~ "\r\n";
        }
        app ~= "\r\n";
        StreamResult result = this.outputStream.writeToStream(cast(ubyte[]) app[]);
        if (result.hasError) {
            throw new Exception("Failed to write headers to output stream: " ~ cast(string) result.error.message);
        }
        flushed = true;
    }

    /**
     * Writes the given input stream of bytes to the response's body.
     * Params:
     *   stream = The stream of bytes to write to the output.
     *   size = The size of the response. This must be known beforehand to set
     *          the "Content-Length" header.
     *   contentType = The content type of the bytes.
     */
    public void writeBody(S)(S stream, ulong size, string contentType) if (isByteInputStream!S) {
        if (!flushed) {
            addHeader("Content-Length", size.to!string);
            addHeader("Content-Type", contentType);
            flushHeaders();
        }
        StreamResult result = transferTo(stream, this.outputStream, Optional!ulong(size));
        if (result.hasError) {
            throw new Exception("Failed to write body to output stream: " ~ cast(string) result.error.message);
        }
        debugF!"Wrote %d bytes to response output stream."(result.count);
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
        this.writeBody(arrayInputStreamFor(data), data.length, contentType);
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
