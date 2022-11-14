/** 
 * Internal parsing utilities for the server's HTTP request processing.
 */
module handy_httpd.parse_utils;

import std.typecons;
import std.conv;
import std.array;
import std.string;
import std.algorithm;
import std.uri;
import httparsed;
import handy_httpd.request : HttpRequest;

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
 * Returns: An HttpRequest object which can be passed to a handler.
 */
public HttpRequest parseRequest(MsgParser!Msg requestParser, string s) {
    // requestParser.msg.m_headersLength = 0; // Reset the parser headers.
    int result = requestParser.parseRequest(s);
    string[string] headers;
    foreach (h; requestParser.headers) {
        headers[h.name] = cast(string) h.value;
    }
    string rawUrl = decode(cast(string) requestParser.uri);
    auto urlAndParams = parseUrlAndParams(rawUrl);
    string bodyContent = null;
    if (result < s.length) {
        bodyContent = s[result .. $];
    }

    return HttpRequest(
        cast(string) requestParser.method,
        urlAndParams[0],
        requestParser.minorVer,
        headers,
        urlAndParams[1],
        null,
        bodyContent
    );
}

/** 
 * Parses a path and set of query parameters from a raw URL string.
 * Params:
 *   rawUrl = The raw url containing both path and query params.
 * Returns: A tuple containing the path and parsed query params.
 */
private Tuple!(string, string[string]) parseUrlAndParams(string rawUrl) {
    Tuple!(string, string[string]) result;
    auto p = rawUrl.indexOf('?');
    if (p == -1) {
        result[0] = rawUrl;
        result[1] = null;
    } else {
        result[0] = rawUrl[0..p];
        result[1] = parseQueryString(rawUrl[p..$]);
    }
    // Strip away a trailing slash if there is one. This makes path matching easier.
    if (result[0][$ - 1] == '/') {
        result[0] = result[0][0 .. $ - 1];
    }
    return result;
}

/** 
 * Parses a set of query parameters from a query string.
 * Params:
 *   queryString = The raw query string to parse, including the preceding '?' character.
 * Returns: An associative array containing parsed params.
 */
private string[string] parseQueryString(string queryString) {
    string[string] params;
    if (queryString.length > 1) {
        string[] paramSections = queryString[1..$].split("&").filter!(s => s.length > 0).array;
        foreach (paramSection; paramSections) {
            string paramName;
            string paramValue;
            auto p = paramSection.indexOf('=');
            if (p == -1 || p + 1 == paramSection.length) {
                paramName = paramSection;
                paramValue = "true";
            } else {
                paramName = paramSection[0..p];
                paramValue = paramSection[p+1..$];
            }
            params[paramName] = paramValue;
        }
    }
    return params;
}
