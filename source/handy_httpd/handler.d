/** 
 * Contains core components for the HTTP handler structure.
 */
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
     *   response = The response to send back to the client.
     */
    void handle(ref HttpRequest request, ref HttpResponse response);
}

/** 
 * Helper method to produce an HttpRequestHandler from a function.
 * Params:
 *   fn = The function that will handle requests.
 * Returns: The request handler.
 */
HttpRequestHandler simpleHandler(void function(ref HttpRequest, ref HttpResponse) fn) {
    return new class HttpRequestHandler {
        void handle(ref HttpRequest request, ref HttpResponse response) {
            fn(request, response);
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
        void handle(ref HttpRequest request, ref HttpResponse response) {
            response.setStatus(503).setStatusText("Service Unavailable").flushHeaders();
        }
    };
}
