/** 
 * Contains core components for the HTTP handler structure.
 */
module handy_httpd.components.handler;

import handy_httpd.components.request;
import handy_httpd.components.response;
import handy_httpd.server;

import std.socket;

/**
 * A simple container for the components that are available in the context of
 * handling an HttpRequest. This includes:
 * - The HttpRequest.
 * - The HttpResponse.
 */
struct HttpRequestContext {
    /**
     * The request that a client sent.
     */
    public HttpRequest request;

    /**
     * The response that
     */
    public HttpResponse response;

    /** 
     * The internal socket that is used to communicate with the client.
     */
    public Socket clientSocket;

    /** 
     * The server from which this context was created.
     */
    public HttpServer server;
}

class HttpRequestContextBuilder {
    import std.socket;
    import handy_httpd.server;

    private HttpServer server;
    private Socket clientSocket;
    private HttpRequestBuilder requestBuilder;

    this(HttpServer server, Socket clientSocket) {
        this.server = server;
        this.clientSocket = clientSocket;
    }

    HttpRequestContextBuilder withRequest(string method, string url) {
        this.requestBuilder = new HttpRequestBuilder(method, url);
        return this;
    }

    HttpRequestContext build() {
        return HttpRequestContext(
            this.requestBuilder.build(),
            HttpResponse(200, "OK", string[string].init, this.clientSocket, false),
            this.clientSocket,
            this.server
        );
    }
}

/** 
 * An alias for the signature of a function capable of handling requests. It's
 * just a `void` function that takes a single `ref HttpRequestContext`
 * parameter. It is acceptable to throw exceptions from the function.
 */
alias HttpRequestHandlerFunction = void function(ref HttpRequestContext);

/** 
 * Interface for any component that handles HTTP requests.
 */
interface HttpRequestHandler {
    /** 
     * Handles an HTTP request. Note that this method may be called from
     * multiple threads, as requests may be processed in parallel.
     * Params:
     *   ctx = The request context.
     */
    void handle(ref HttpRequestContext ctx);
}

/** 
 * A specialized handler which is used for situations in which you'd like to
 * gracefully handle an exception that occurs during processing a request.
 */
interface ServerExceptionHandler {
    /** 
     * Handles an HTTP request associated with an exception.
     * Params:
     *   ctx = The request context.
     *   e = The exception that was thrown.
     */
    void handle(ref HttpRequestContext ctx, Exception e);
}

/** 
 * A basic implementation of the `ServerExceptionHandler` which just logs the
 * exception, and if possible, sends a 500 response to the client which just
 * indicates that an error occurred.
 */
class BasicServerExceptionHandler : ServerExceptionHandler {
    void handle(ref HttpRequestContext ctx, Exception e) {
        auto log = ctx.server.getLogger();
        log.infoF!"An error occurred while handling a request: %s"(e.msg);
        if (!ctx.response.isFlushed) {
            ctx.response.setStatus(500);
            ctx.response.setStatusText("Internal Server Error");
            ctx.response.addHeader("Content-Type", "text/plain");
            ctx.response.writeBody("An error occurred while handling your request.");
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
HttpRequestHandler toHandler(HttpRequestHandlerFunction fn) {
    return new class HttpRequestHandler {
        void handle(ref HttpRequestContext ctx) {
            fn(ctx);
        }
    };
}

/** 
 * Helper method for an HttpRequestHandler that simply responds with a 503 to
 * any request.
 * Returns: The request handler.
 */
HttpRequestHandler noOpHandler() {
    return toHandler((ref ctx) {
        ctx.response.setStatus(503)
            .setStatusText("Service Unavailable")
            .flushHeaders();
    });
}
