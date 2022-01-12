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
    ushort status;

    /** 
     * A short textual representation of the status.
     */
    string statusText;

    /** 
     * An associative array of headers.
     */
    string[string] headers;

    /** 
     * The body of the message.
     */
    ubyte[] messageBody;

    HttpResponse setStatus(ushort status) {
        this.status = status;
        return this;
    }

    HttpResponse setStatusText(string statusText) {
        this.statusText = statusText;
        return this;
    }

    HttpResponse addHeader(string name, string value) {
        this.headers[name] = value;
        return this;
    }

    HttpResponse setBody(string messageBody) {
        this.messageBody = cast(ubyte[]) messageBody;
        return this;
    }

    /** 
     * Converts this response to a byte array in HTTP format.
     * Returns: A byte array containing the response content.
     */
    ubyte[] toBytes() {
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
