/** 
 * Contains HTTP response components.
 */
module handy_httpd.response;

import std.array;
import std.string : format, representation;
import std.conv;

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
     * The body of the message.
     */
    public ubyte[] messageBody;

    /** 
     * Sets the status of the response.
     * Params:
     *   status = The status code.
     * Returns: The response object, for method chaining.
     */
    public HttpResponse setStatus(ushort status) {
        this.status = status;
        return this;
    }

    /** 
     * Sets the status text of the response.
     * Params:
     *   statusText = The status text.
     * Returns: The response object, for method chaining.
     */
    public HttpResponse setStatusText(string statusText) {
        this.statusText = statusText;
        return this;
    }

    /** 
     * Adds a header to the response.
     * Params:
     *   name = The name of the header.
     *   value = The value to set for the header.
     * Returns: The response object, for method chaining.
     */
    public HttpResponse addHeader(string name, string value) {
        this.headers[name] = value;
        return this;
    }

    /** 
     * Sets the body of the response.
     * Params:
     *   messageBody = The message body to send.
     * Returns: The response object, for method chaining.
     */
    public HttpResponse setBody(string messageBody) {
        this.messageBody = cast(ubyte[]) messageBody;
        return this;
    }

    /** 
     * Converts this response to a byte array in HTTP format.
     * Returns: A byte array containing the response content.
     */
    public ubyte[] toBytes() {
        auto a = appender!(ubyte[]);
        auto statusLine = format!"HTTP/1.1 %d %s\r\n"(status, statusText);
        a ~= cast(ubyte[]) statusLine;
        if (messageBody.length > 0) {
            headers["Content-Length"] = messageBody.length.to!string;
        }
        foreach (name, value; headers) {
            a ~= cast(ubyte[]) (name ~ ": " ~ value ~ "\r\n");
        }
        a ~= cast(ubyte[]) "\r\n";
        if (messageBody.length > 0) {
            a ~= messageBody;
        }
        return a[];
    }
}
