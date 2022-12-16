/** 
 * Contains HTTP request components.
 */
module handy_httpd.components.request;

import handy_httpd.server: HttpServer;
import handy_httpd.components.response : HttpResponse;

/** 
 * The data which the server provides to HttpRequestHandlers so that they can
 * formulate a response.
 */
struct HttpRequest {
    /** 
     * The HTTP method verb, such as GET, POST, PUT, etc.
     */
    public const string method;

    /** 
     * The url of the request, excluding query parameters.
     */
    public const string url;

    /** 
     * The request version.
     */
    public const int ver;

    /** 
     * An associative array containing all request headers.
     */
    public const string[string] headers;

    /** 
     * An associative array containing all request params, if any were given.
     */
    public const string[string] params;

    /** 
     * An associative array containing any path parameters obtained from the
     * request url. These are only populated in cases where it is possible to
     * parse path parameters, such as with a PathDelegatingHandler.
     */
    public string[string] pathParams;

    /** 
     * A string containing the body content of the request. This may be null,
     * if the request doesn't have a body.
     */
    public string bodyContent;

    /** 
     * Determines if this request has a non-empty body.
     * Returns: True if this request's body is not null, and not empty.
     */
    public bool hasBody() {
        return bodyContent !is null && bodyContent.length > 0;
    }

    import std.json;

    /** 
     * Gets the body of this request as a JSON value.
     * Returns: The parsed JSONValue representing the body. If the body is
     * empty, an empty JSON object is returned.
     */
    public JSONValue bodyAsJson() {
        if (!hasBody) return JSONValue(string[string].init);
        return parseJSON(bodyContent);
    }

    /** 
     * Gets a URL parameter as the specified type, or returns the default value
     * if the parameter with the given name doesn't exist.
     * Params:
     *   name = The name of the URL parameter.
     *   defaultValue = The default value to return if the URL parameter
     *                  doesn't exist.
     * Returns: The value of the URL parameter.
     */
    public T getParamAs(T)(string name, T defaultValue = T.init) {
        import std.conv : to;
        if (name !in params) return defaultValue;
        return params[name].to!T;
    }

    unittest {
        HttpRequest req = HttpRequest(
            "GET",
            "/api",
            1,
            string[string].init,
            [
                "a": "123",
                "b": "c",
                "c": "true"
            ],
            string[string].init,
            ""
        );
        assert(req.getParamAs!int("a") == 123);
        assert(req.getParamAs!char("b") == 'c');
        assert(req.getParamAs!bool("c") == true);
        assert(req.getParamAs!int("d") == 0);
    }

    /** 
     * Gets a path parameter as the specified type, or returns the default
     * value if the path parameter with the given name doesn't exist.
     * Params:
     *   name = The name of the path parameter.
     *   defaultValue = The default value to return if the path parameter
     *                  doesn't exist.
     * Returns: The value of the path parameter.
     */
    public T getPathParamAs(T)(string name, T defaultValue = T.init) {
        import std.conv : to;
        if (name !in pathParams) return defaultValue;
        return pathParams[name].to!T;
    }

    unittest {
        HttpRequest req;
        req.pathParams = [
            "a": "123",
            "b": "c",
            "c": "true"
        ];
        assert(req.getPathParamAs!int("a") == 123);
        assert(req.getPathParamAs!char("b") == 'c');
        assert(req.getPathParamAs!bool("c") == true);
        assert(req.getPathParamAs!int("d") == 0);
    }
}

/** 
 * A utility class for a fluent interface for building requests. This is useful
 * for testing.
 */
class HttpRequestBuilder {
    string method;
    string url;
    string[string] headers;
    string[string] params;
    string[string] pathParams;
    string bodyContent;

    this(string method, string url) {
        this.method = method;
        this.url = url;
    }

    HttpRequestBuilder withHeader(string name, string value) {
        this.headers[name] = value;
        return this;
    }

    HttpRequestBuilder withParam(string name, string value) {
        this.params[name] = value;
        return this;
    }

    HttpRequestBuilder withPathParam(string name, string value) {
        this.pathParams[name] = value;
        return this;
    }

    HttpRequestBuilder withBodyContent(string content) {
        this.bodyContent = content;
        return this;
    }

    HttpRequest build() {
        return HttpRequest(
            this.method,
            this.url,
            1,
            this.headers,
            this.params,
            this.pathParams,
            this.bodyContent
        );
    }
}
