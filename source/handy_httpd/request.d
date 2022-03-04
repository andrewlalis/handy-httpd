/** 
 * Contains HTTP request components.
 */
module handy_httpd.request;

import std.socket : Socket;
import handy_httpd.server: HttpServer;
import handy_httpd.response : HttpResponse;

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
     * A reference to the HttpServer that is handling this request.
     */
    public HttpServer server;

    /** 
     * The underlying socket that the request was received from, and to which
     * the response will be written.
     */
    public Socket clientSocket;
}
