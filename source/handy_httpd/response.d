module handy_httpd.response;

import std.string : format, representation;

struct HttpResponse {
    public ushort status;
    public string statusText;

    ubyte[] toBytes() {
        auto s = format!"HTTP/1.1 %d %s\n\n"(status, statusText);
        return cast(ubyte[]) representation(s);
    }
}
