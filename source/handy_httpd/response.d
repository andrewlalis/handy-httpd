/** 
 * Contains HTTP response components.
 */
module handy_httpd.response;

import std.array;
import std.string : format, representation;
import std.conv;
import std.socket : Socket;

/** 
 * The data that the HTTP server will send back to clients.
 */
struct HttpResponse {
    /** 
     * The status code.
     */
    public ushort status;

    /** 
     * A short textual representation of the status.
     */
    public string statusText;

    /** 
     * An associative array of headers.
     */
    public string[string] headers;

    /** 
     * The socket that's used to send data to the client.
     */
    public Socket clientSocket;

    private bool flushed = false;

    /** 
     * Sets the status of the response. This can only be done before headers
     * are flushed.
     * Params:
     *   status = The status code.
     * Returns: The response object, for method chaining.
     */
    public HttpResponse setStatus(ushort status) {
        if (flushed) throw new Exception("Cannot modify header after it's been flushed.");
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
        if (flushed) throw new Exception("Cannot modify header after it's been flushed.");
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
        if (flushed) throw new Exception("Cannot modify header after it's been flushed.");
        this.headers[name] = value;
        return this;
    }

    /** 
     * Flushes the headers for this request, sending them on the socket to the
     * client. Once this is done, header information can no longer be modified.
     */
    public void flushHeaders() {
        if (flushed) return;
        auto app = appender!string;
        app ~= format!"HTTP/1.1 %d %s\r\n"(this.status, this.statusText);
        foreach (name, value; this.headers) {
            app ~= format!"%s: %s\r\n"(name, value);
        }
        app ~= "\r\n";
        ubyte[] data = cast(ubyte[]) app[];
        auto sent = this.clientSocket.send(data);
        if (sent == Socket.ERROR) throw new Exception("Socket error occurred while writing status and headers.");
        flushed = true;
    }

    /** 
     * Writes the given string content to the body of the response. If this
     * response has not yet written its status line and headers, it will do
     * that first.
     * Params:
     *   body = The content to write.
     */
    public void writeBody(string body) {
        if (!flushed) addHeader("Content-Length", body.length.to!string);
        flushHeaders();
        auto sent = this.clientSocket.send(cast(ubyte[]) body);
        if (sent == Socket.ERROR) throw new Exception("Socket error occurred while writing body.");
    }

    /** 
     * Tells whether the header of this response has already been flushed.
     * Returns: Whether the response headers have been flushed.
     */
    public bool isFlushed() {
        return flushed;
    }
}
