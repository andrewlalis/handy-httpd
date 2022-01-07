module handy_httpd.handler;

import handy_httpd.request;
import handy_httpd.response;

/** 
 * Interface for any component that handles HTTP requests.
 */
interface HttpRequestHandler {
    /** 
     * Handles an HTTP request. Note that this method may be called from
     * multiple threads, as requests may be processed in parallel.
     * Params:
     *   request = The request to handle.
     * Returns: An HTTP response to send to the client.
     */
    HttpResponse handle(HttpRequest request);
}

/** 
 * Helper method to produce an HttpRequestHandler from a function.
 * Params:
 *   fn = The function that will handle requests.
 * Returns: The request handler.
 */
HttpRequestHandler simpleHandler(HttpResponse function(HttpRequest) fn) {
    return new class HttpRequestHandler {
        HttpResponse handle(HttpRequest request) {
            return fn(request);
        }
    };
}

/** 
 * Helper method for an HttpRequestHandler that simply responds with a 503 to
 * any request.
 * Returns: The request handler.
 */
HttpRequestHandler noOpHandler() {
    return new class HttpRequestHandler {
        HttpResponse handle(HttpRequest request) {
            return HttpResponse(503, "Service Unavailable", null, null);
        }
    };
}
