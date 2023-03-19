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
     * The status code.
     */
    public ushort status = 200;

    /** 
     * A short textual representation of the status.
     */
    public string statusText = "OK";

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
     *   status = The status code.
     * Returns: The response object, for method chaining.
     */
    public HttpResponse setStatus(ushort status) {
        if (flushed) {
            warnF!"Attempted to set status to %d after the response has already been flushed."(status);
        }
        this.status = status;
        return this;
    }

    /** 
     * Sets the status text of the response. This can only be done before
     * headers are flushed.
     * Params:
     *   statusText = The status text.
     * Returns: The response object, for method chaining.
     */
    public HttpResponse setStatusText(string statusText) {
        if (flushed) {
            warnF!"Attempted to set statusText to \"%s\" after the response has already been flushed."(statusText);
        }
        this.statusText = statusText;
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
        app ~= format!"HTTP/1.1 %d %s\r\n"(this.status, this.statusText);
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
