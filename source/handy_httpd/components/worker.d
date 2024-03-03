/** 
 * This module contains the logic for each server worker, which involves
 * parsing and handling incoming requests.
 */
module handy_httpd.components.worker;

import std.socket : Socket, SocketShutdown;
import std.typecons;

import handy_httpd.server : HttpServer;
import handy_httpd.components.parse_utils : Msg, receiveRequest;
import handy_httpd.components.context;
import http_primitives;
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
    ubyte[] receiveBuffer,
    ref MsgParser!Msg requestParser,
    Logger logger = getLogger()
) {
    if (socket is null) return; // If for whatever reason a null socket is provided, quit.
    if (!socket.isAlive) {
        socket.close();
        return;
    }
    logger.debug_("Got client socket.");
    // Try to parse and build a request context by reading from the socket.
    SocketInputRange inputRange = SocketInputRange(socket, receiveBuffer);
    SocketOutputRange outputRange = SocketOutputRange(socket);
    auto optionalCtx = receiveRequest(
        server, socket,
        &inputRange, &outputRange,
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
    Tuple!(HttpRequest, HttpResponse) ctx = optionalCtx.value;
    HttpRequest request = ctx[0];
    HttpResponse response = ctx[1];
    REQUEST_CONTEXT.server = server;
    logger.infoF!"Request: Method=%s, URL=\"%s\""(request.method, request.url);
    try {
        server.getHandler.handle(request, response);
        if (!response.isFlushed) {
            response.flushHeaders();
        }
    } catch (Exception e) {
        logger.debugF!"Encountered exception %s while handling request: %s"(e.classinfo.name, e.msg);
        try {
            server.getExceptionHandler.handle(request, response, e);
        } catch (Exception e2) {
            logger.error("Exception occurred in the server's exception handler.", e2);
        }
    }
    // Only close the socket if we're not switching protocols.
    if (response.status != HttpStatus.SWITCHING_PROTOCOLS) {
        socket.shutdown(SocketShutdown.BOTH);
        socket.close();
        // Destroy the request context's allocated objects.
        destroy!(false)(request.inputRange);
        destroy!(false)(response.outputRange);
    } else {
        logger.debug_("Keeping socket alive due to SWITCHING_PROTOCOLS status.");
    }

    logger.infoF!"Response: Status=%d %s"(response.status.code, response.status.text);

    // Reset the request parser so we're ready for the next request.
    requestParser.msg.reset();
}

struct SocketOutputRange {
    private Socket socket;

    void put(ubyte[] data) {
        ptrdiff_t sent = socket.send(data);
        if (sent != data.length) throw new Exception("Couldn't send all data.");
    }
}

struct SocketInputRange {
    private Socket socket;
    private ubyte[] buffer;
    private size_t bytesAvailable;
    bool closed = false;

    bool empty() {
        return socket is null || closed || !socket.isAlive;
    }

    ubyte[] front() {
        return buffer[0 .. bytesAvailable];
    }

    void popFront() {
        if (closed || socket is null) return;
        ptrdiff_t readCount = socket.receive(buffer);
        if (readCount == 0 || readCount == Socket.ERROR) {
            closed = true;
        } else {
            bytesAvailable = readCount;
        }
    }
}
