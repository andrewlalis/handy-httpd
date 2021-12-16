module handy_httpd.response;

import std.array;
import std.string : format, representation;
import std.conv;

HttpResponse okResponse() {
    return HttpResponse(200, "OK", null, "");
}

HttpResponse fileResponse(string filename, string type) {
    import std.file;
    if (!exists(filename)) {
        return HttpResponse(404, "Not Found", null, null)
            .addHeader("Content-Type", type);
    } else {
        return HttpResponse(200, "OK", null, readText(filename))
            .addHeader("Content-Type", type);
    }
}

struct HttpResponse {
    ushort status;
    string statusText;
    string[string] headers;
    string messageBody;

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
        this.messageBody = messageBody;
        return this;
    }

    ubyte[] toBytes() {
        auto a = appender!string;
        auto statusLine = format!"HTTP/1.1 %d %s\r\n"(status, statusText);
        a ~= statusLine;
        if (messageBody.length > 0) {
            headers["Content-Length"] = messageBody.length.to!string;
        }
        foreach (name, value; headers) {
            a ~= name ~ ": " ~ value ~ "\r\n";
        }
        a ~= "\r\n";
        if (messageBody.length > 0) {
            a ~= messageBody;
        }
        return cast(ubyte[]) representation(a[]);
    }
}
