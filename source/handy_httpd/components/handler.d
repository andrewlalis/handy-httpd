/** 
 * Contains core components for the HTTP handler structure.
 */
module handy_httpd.components.handler;

import handy_httpd.components.request;
import handy_httpd.components.response;
import handy_httpd.components.worker;
import handy_httpd.server;

import std.range : InputRange, OutputRange;
import std.conv : to;
import slf4d;

/**
 * A simple container for the components that are available in the context of
 * handling an HttpRequest. This includes:
 * - The HttpRequest.
 * - The HttpResponse.
 * - The HttpServer.
 * - The worker thread.
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
     * The server from which this context was created.
     */
    public HttpServer server;

    /** 
     * The worker thread that's handling this request.
     */
    public ServerWorkerThread worker;
}

/** 
 * An alias for the signature of a function capable of handling requests. It's
 * just a `void` function that takes a single `HttpRequestContext` parameter.
 * It is acceptable to throw exceptions from the function.
 */
alias HttpRequestHandlerFunction = void function(ref HttpRequestContext);

/** 
 * Interface for any component that handles HTTP requests.
 */
interface HttpRequestHandler {
    /** 
     * Handles an HTTP request. Note that this method may be called from
     * multiple threads, as requests may be processed in parallel, so you
     * should avoid performing actions which are not thread-safe.
     *
     * The context `ctx` is passed as a `ref` because the context ultimately
     * belongs to the worker that's handling the request.
     *
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
 * An exception that can be thrown to indicate that the current request should
 * immediately respond with a specified status, short-circuiting any other
 * handler logic. Note that it is still the responsibility of the server's
 * exception handler to honor this exception, but by default, the `BasicServerExceptionHandler`
 * does honor it.
 */
class HttpStatusException : Exception {
    public immutable HttpStatus status;
    public immutable string message;

    public this(HttpStatus status, string message = null) {
        super("Http " ~ status.code.to!string ~ " " ~ status.text ~ ": " ~ message);
        this.status = status;
        this.message = message;
    }
}

/** 
 * A basic implementation of the `ServerExceptionHandler` which just logs the
 * exception, and if possible, sends a 500 response to the client which just
 * indicates that an error occurred.
 */
class BasicServerExceptionHandler : ServerExceptionHandler {
    void handle(ref HttpRequestContext ctx, Exception e) {
        auto log = getLogger();
        if (auto statusExc = cast(HttpStatusException) e) {
            log.debugF!"Handling HttpStatusException: %d %s"(statusExc.status.code, statusExc.status.text);
            if (!ctx.response.isFlushed) {
                ctx.response.setStatus(statusExc.status);
                if (statusExc.message !is null) {
                    ctx.response.writeBodyString(statusExc.message);
                }
            } else {
                log.error("The response has already been flushed; cannot send HttpStatusException status.");
            }
        } else {
            log.errorF!"An error occurred while handling a request: %s"(e.msg);
            if (!ctx.response.isFlushed) {
                ctx.response.setStatus(HttpStatus.INTERNAL_SERVER_ERROR);
                ctx.response.writeBodyString("An error occurred while handling your request.");
            } else {
                log.error("The response has already been sent; cannot send 500 error.");
            }
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
        ctx.response.setStatus(HttpStatus.SERVICE_UNAVAILABLE);
    });
}
