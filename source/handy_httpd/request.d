/** 
 * Contains HTTP request components.
 */
module handy_httpd.request;

import handy_httpd.server;

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
     * A reference to the HttpServer that is handling this request.
     */
    public HttpServer server;
}
