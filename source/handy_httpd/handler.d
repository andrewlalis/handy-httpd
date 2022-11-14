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
 * A specialized handler which is used for situations in which you'd like to
 * gracefully handle an exception that occurs during processing a request.
 */
interface ServerExceptionHandler {
    /** 
     * Handles an HTTP request associated with an exception.
     * Params:
     *   request = The HTTP request.
     *   response = The response to send back to the client.
     *   e = The exception that was thrown.
     */
    void handle(ref HttpRequest request, ref HttpResponse response, Exception e);
}

/** 
 * A basic implementation of the `ServerExceptionHandler` which just logs the
 * exception, and if possible, sends a 500 response to the client which just
 * indicates that an error occurred.
 */
class BasicServerExceptionHandler : ServerExceptionHandler {
    void handle(ref HttpRequest request, ref HttpResponse response, Exception e) {
        auto log = request.server.getLogger();
        log.infoF!"An error occurred while handling a request: %s"(e.msg);
        if (!response.isFlushed) {
            response.setStatus(500);
            response.setStatusText("Internal Server Error");
            response.addHeader("Content-Type", "text/plain");
            response.writeBody("An error occurred while handling your request.");
        } else {
            log.infoV("The response has already been sent; cannot send 500 error.");
        }
    }
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
