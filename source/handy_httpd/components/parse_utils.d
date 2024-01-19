/**
 * Internal parsing utilities for the server's HTTP request processing.
 */
module handy_httpd.components.parse_utils;

import std.typecons;
import std.conv;
import std.array;
import std.string;
import std.algorithm;
import std.uri;
import std.range;
import httparsed;

import handy_httpd.components.request : HttpRequest, methodFromName;
import handy_httpd.components.form_urlencoded;

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
 * Returns: A tuple containing the http request and the size of data read.
 */
public Tuple!(HttpRequest, int) parseRequest(MsgParser!Msg requestParser, string s) {
    int result = requestParser.parseRequest(s);
    if (result < 1) {
        throw new Exception("Couldn't parse header.");
    }
    
    string[string] headers;
    foreach (h; requestParser.headers) {
        headers[h.name] = cast(string) h.value;
    }
    string rawUrl = decode(cast(string) requestParser.uri);
    Tuple!(string, QueryParam[]) urlAndParams = parseUrlAndParams(rawUrl);
    string method = cast(string) requestParser.method;
    HttpRequest request = HttpRequest(
        methodFromName(method),
        urlAndParams[0],
        requestParser.minorVer,
        headers,
        QueryParam.toMap(urlAndParams[1]),
        urlAndParams[1],
        null
    );
    return tuple(request, result);
}

/**
 * Parses a path and set of query parameters from a raw URL string.
 * **Deprecated** because handy-httpd is transitioning away from AA-style
 * query params. You should use `parseUrlAndParams` instead.
 * Params:
 *   rawUrl = The raw url containing both path and query params.
 * Returns: A tuple containing the path and parsed query params.
 */
public Tuple!(string, string[string]) parseUrlAndParamsAsMap(string rawUrl) {
    Tuple!(string, string[string]) result;
    auto p = rawUrl.indexOf('?');
    if (p == -1) {
        result[0] = rawUrl;
        result[1] = null;
    } else {
        result[0] = rawUrl[0..p];
        result[1] = QueryParam.toMap(parseFormUrlEncoded(rawUrl[p..$], false));
    }
    // Strip away a trailing slash if there is one. This makes path matching easier.
    if (result[0][$ - 1] == '/') {
        result[0] = result[0][0 .. $ - 1];
    }
    return result;
}

/**
 * Parses a path and set of query parameters from a raw URL string.
 * Params:
 *   rawUrl = The raw url containing both path and query params.
 * Returns: A tuple containing the path and parsed query params.
 */
public Tuple!(string, QueryParam[]) parseUrlAndParams(string rawUrl) {
    Tuple!(string, QueryParam[]) result;
    auto p = rawUrl.indexOf('?');
    if (p == -1) {
        result[0] = rawUrl;
    } else {
        result[0] = rawUrl[0..p];
        result[1] = parseFormUrlEncoded(rawUrl[p..$], false);
    }
    // Strip away a trailing slash if there is one. This makes path matching easier.
    if (result[0][$ - 1] == '/') {
        result[0] = result[0][0 .. $ - 1];
    }
    return result;
}
