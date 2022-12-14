/** 
 * Contains HTTP request components.
 */
module handy_httpd.components.request;

import std.socket : Socket;

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
     * A reference to the HttpServer that is handling this request.
     */
    public HttpServer server;

    /** 
     * The underlying socket that the request was received from, and to which
     * the response will be written.
     */
    public Socket clientSocket;

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
}
