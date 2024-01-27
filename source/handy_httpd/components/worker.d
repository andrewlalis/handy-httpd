/** 
 * This module contains the logic for each server worker, which involves
 * parsing and handling incoming requests.
 */
module handy_httpd.components.worker;

import std.socket : Socket, SocketShutdown;

import handy_httpd.server : HttpServer;
import handy_httpd.components.parse_utils : Msg, receiveRequest;
import handy_httpd.components.handler : HttpRequestContext;
import handy_httpd.components.response : HttpStatus;

import streams : SocketInputStream, SocketOutputStream;
import httparsed : MsgParser;
import slf4d;

/**
 * The main logical function that's called when a new client socket is accepted
 * which receives the request, handles it, and then closes the socket and frees
 * any allocated resources.
 * Params:
 *   server = The server that accepted the client.
 *   socket = The client's socket.
 *   receiveBuffer = A preallocated buffer for reading the client's request.
 *   requestParser = The HTTP request parser.
 *   logger = A logger to use for any logging messages.
 */
public void handleClient(
    HttpServer server,
    Socket socket,
    ref ubyte[] receiveBuffer,
    ref MsgParser!Msg requestParser,
    Logger logger = getLogger()
) {
    if (socket is null) return; // If for whatever reason a null socket is provided, quit.
    if (!socket.isAlive) {
        socket.close();
        return;
    }
    logger.debug_("Got client socket.");
    // Create the input and output streams for the request here, since their
    // lifetime continues until the request is handled.
    SocketInputStream inputStream = SocketInputStream(socket);
    SocketOutputStream outputStream = SocketOutputStream(socket);
    // Try to parse and build a request context by reading from the socket.
    auto optionalCtx = receiveRequest(
        server, socket,
        &inputStream, &outputStream,
        receiveBuffer,
        requestParser,
        logger
    );
    if (optionalCtx.isNull) {
        logger.debug_("Skipping this request because we couldn't get a context.");
        socket.shutdown(SocketShutdown.BOTH);
        socket.close();
        return;
    }

    // We successfully got a request, so use the server's handler to handle it.
    HttpRequestContext ctx = optionalCtx.value;
    logger.infoF!"Request: Method=%s, URL=\"%s\""(ctx.request.method, ctx.request.url);
    try {
        server.getHandler.handle(ctx);
        if (!ctx.response.isFlushed) {
            ctx.response.flushHeaders();
        }
    } catch (Exception e) {
        logger.debugF!"Encountered exception %s while handling request: %s"(e.classinfo.name, e.msg);
        try {
            server.getExceptionHandler.handle(ctx, e);
        } catch (Exception e2) {
            logger.error("Exception occurred in the server's exception handler.", e2);
        }
    }
    // Only close the socket if we're not switching protocols.
    if (ctx.response.status != HttpStatus.SWITCHING_PROTOCOLS) {
        socket.shutdown(SocketShutdown.BOTH);
        socket.close();
        // Destroy the request context's allocated objects.
        destroy!(false)(ctx.request.inputStream);
        destroy!(false)(ctx.response.outputStream);
        destroy!(false)(ctx.metadata);
    } else {
        logger.debug_("Keeping socket alive due to SWITCHING_PROTOCOLS status.");
    }

    logger.infoF!"Response: Status=%d %s"(ctx.response.status.code, ctx.response.status.text);

    // Reset the request parser so we're ready for the next request.
    requestParser.msg.reset();
}
