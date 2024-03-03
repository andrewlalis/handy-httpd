/** 
 * Contains core components for the HTTP handler structure.
 */
module handy_httpd.components.handler;

import handy_httpd.components.worker;
import handy_httpd.server;
import http_primitives;

import std.range : InputRange, OutputRange;
import std.conv : to;
import std.socket : Socket;
import slf4d;

/**
 * A specialized handler which is used for situations in which you'd like to
 * gracefully handle an exception that occurs during processing a request.
 */
interface ServerExceptionHandler {
    /**
     * Handles an HTTP request associated with an exception.
     */
    void handle(ref HttpRequest request, ref HttpResponse response, Exception e);
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
 * A basic implementation of the `ServerExceptionHandler` which gracefully
 * handles `HttpStatusException` by setting the response status, and defaults
 * to a 500 INTERNAL SERVER ERROR respones for all other exceptions. If the
 * response has already been flushed, an error will be logged.
 */
class BasicServerExceptionHandler : ServerExceptionHandler {
    void handle(ref HttpRequest request, ref HttpResponse response, Exception e) {
        if (response.isFlushed) {
            error("Response is already flushed; cannot handle exception.", e);
            return;
        }
        if (auto statusExc = cast(HttpStatusException) e) {
            handleHttpStatusException(response, statusExc);
        } else {
            handleOtherException(response, e);
        }
    }

    protected void handleHttpStatusException(ref HttpResponse response, HttpStatusException e) {
        debugF!"Handling HttpStatusException: %d %s"(e.status.code, e.status.text);
        response.status = e.status;
        if (e.message !is null) {
            response.writeBodyString(e.message);
        }
    }

    protected void handleOtherException(ref HttpResponse response, Exception e) {
        error("An error occurred while handling a request.", e);
        response.status = HttpStatus.INTERNAL_SERVER_ERROR;
        response.writeBodyString("An error occurred while handling your request.");
    }
}
