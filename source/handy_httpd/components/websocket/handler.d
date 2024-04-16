/**
 * Defines components relating to how websocket messages and initial HTTP
 * requests are handled.
 */
module handy_httpd.components.websocket.handler;

import handy_httpd.components.socket_range;
import http_primitives;
import slf4d;

/**
 * An exception that's thrown if an unexpected situation arises while dealing
 * with a websocket connection.
 */
class WebSocketException : Exception {
    import std.exception : basicExceptionCtors;
    mixin basicExceptionCtors;
}

/**
 * A text-based websocket message.
 */
struct WebSocketTextMessage {
    WebSocketConnection conn;
    string payload;
}

/**
 * A binary websocket message.
 */
struct WebSocketBinaryMessage {
    WebSocketConnection conn;
    ubyte[] payload;
}

/**
 * A "close" control websocket message indicating the client is closing the
 * connection.
 */
struct WebSocketCloseMessage {
    WebSocketConnection conn;
    ushort statusCode;
    string message;
}

/**
 * An abstract class that you should extend to define logic for handling
 * websocket messages and events. Create a new class that inherits from this
 * one, and overrides any "on..." methods that you'd like.
 */
abstract class WebSocketMessageHandler {
    /**
     * Called when a new websocket connection is established.
     * Params:
     *   conn = The new connection.
     */
    void onConnectionEstablished(WebSocketConnection conn) {}

    /**
     * Called when a text message is received.
     * Params:
     *   msg = The message that was received.
     */
    void onTextMessage(WebSocketTextMessage msg) {}

    /**
     * Called when a binary message is received.
     * Params:
     *   msg = The message that was received.
     */
    void onBinaryMessage(WebSocketBinaryMessage msg) {}

    /**
     * Called when a CLOSE message is received. Note that this is called before
     * the socket is necessarily guaranteed to be closed.
     * Params:
     *   msg = The close message.
     */
    void onCloseMessage(WebSocketCloseMessage msg) {}

    /**
     * Called when a websocket connection is closed.
     * Params:
     *   conn = The connection that was closed.
     */
    void onConnectionClosed(WebSocketConnection conn) {}
}

/**
 * All the data that represents a WebSocket connection tracked by the
 * `WebSocketHandler`.
 */
class WebSocketConnection {
    import std.uuid : UUID, randomUUID;
    import std.socket : Socket, SocketShutdown;
    import handy_httpd.components.websocket.frame;

    /**
     * The internal id Handy-Httpd has assigned to this connection.
     */
    public immutable UUID id;

    /**
     * The underlying socket used to communicate with this connection.
     */
    private Socket socket;

    /**
     * The message handler that is called to handle this connection's events.
     */
    private WebSocketMessageHandler messageHandler;

    this(Socket socket, WebSocketMessageHandler messageHandler) {
        this.socket = socket;
        this.messageHandler = messageHandler;
        this.id = randomUUID();
    }

    Socket getSocket() {
        return this.socket;
    }

    WebSocketMessageHandler getMessageHandler() {
        return this.messageHandler;
    }

    /**
     * Sends a text message to the connected client.
     * Params:
     *   text = The text to send. Should be valid UTF-8.
     */
    void sendTextMessage(string text) {
        throwIfClosed();
        sendWebSocketTextFrame(SocketOutputRange(this.socket), text);
    }

    /**
     * Sends a binary message to the connected client.
     * Params:
     *   bytes = The binary data to send.
     */
    void sendBinaryMessage(ubyte[] bytes) {
        throwIfClosed();
        sendWebSocketBinaryFrame(SocketOutputRange(this.socket), bytes);
    }

    /**
     * Sends a close message to the client, indicating that we'll be closing
     * the connection.
     * Params:
     *   status = The status code for closing.
     *   message = A message explaining why we're closing. Length must be <= 123.
     */
    void sendCloseMessage(WebSocketCloseStatusCode status, string message) {
        throwIfClosed();
        sendWebSocketCloseFrame(SocketOutputRange(this.socket), status, message);
    }

    /**
     * Helper method to throw a WebSocketException if our socket is no longer
     * alive, so we know right away if the connection stopped abruptly.
     */
    private void throwIfClosed() {
        if (!this.socket.isAlive()) {
            throw new WebSocketException("Connection " ~ this.id.toString() ~ "'s socket is closed.");
        }
    }

    /**
     * Closes this connection, if it's alive, sending a websocket close message.
     */
    void close() {
        if (this.socket.isAlive()) {
            try {
                this.sendCloseMessage(WebSocketCloseStatusCode.NORMAL, null);
            } catch (WebSocketException e) {
                warn("Failed to send a CLOSE message when closing connection " ~ this.id.toString(), e);
            }
            this.socket.shutdown(SocketShutdown.BOTH);
            this.socket.close();
            this.messageHandler.onConnectionClosed(this);
        }
    }
}

/**
 * A special HttpRequestHandler implementation that exclusively handles
 * websocket connection handshakes.
 */
class WebSocketHandler : HttpRequestHandler {
    private WebSocketMessageHandler messageHandler;

    /**
     * Constructs the websocket handler using the given message handler for
     * any websocket messages received via this handler.
     * Params:
     *   messageHandler = The message handler to use.
     */
    this(WebSocketMessageHandler messageHandler) {
        this.messageHandler = messageHandler;
    }

    /**
     * Handles an HTTP request by verifying that it's a legitimate websocket
     * request, then sends a 101 SWITCHING PROTOCOLS response, and finally,
     * registers a new websocket connection with the server's manager. If an
     * invalid request is given, then a client error response code will be
     * sent back.
     * Params:
     *   ctx = The request context.
     */
    void handle(ref HttpRequest request, ref HttpResponse response) {
        if (!this.verifyRequest(request, response)) return;
        this.sendSwitchingProtocolsResponse(request, response);
        // ctx.server.getWebSocketManager().registerConnection(null, this.messageHandler);
    }

    /**
     * Verifies a websocket request.
     * Params:
     *   ctx = The request context to verify.
     * Returns: True if the request is valid can a websocket connection can be
     * created, or false if we should reject. A response message will already
     * be written in that case.
     */
    private bool verifyRequest(ref HttpRequest request, ref HttpResponse response) {
        string origin = request.headers.getFirst("origin").orElse(null);
        // TODO: Verify correct origin.
        if (request.method != Method.GET) {
            response.status = HttpStatus.METHOD_NOT_ALLOWED;
            response.writeBodyString("Only GET requests are allowed.");
            return false;
        }
        string key = request.headers.getFirst("Sec-WebSocket-Key").orElse(null);
        if (key is null) {
            response.status = HttpStatus.BAD_REQUEST;
            response.writeBodyString("Missing Sec-WebSocket-Key header.");
            return false;
        }
        bool supportsWebsockets = true; // TODO: Check if server supports websockets!
        if (!supportsWebsockets) {
            response.status = HttpStatus.SERVICE_UNAVAILABLE;
            response.writeBodyString("This server does not support websockets.");
            return false;
        }
        return true;
    }

    /**
     * Sends an HTTP 101 SWITCHING PROTOCOLS response to a client, to indicate
     * that we'll be switching to the websocket protocol for all future
     * communications.
     * Params:
     *   ctx = The request context to send the response to.
     */
    private void sendSwitchingProtocolsResponse(ref HttpRequest request, ref HttpResponse response) {
        string key = request.headers.getFirst("Sec-WebSocket-Key").orElseThrow();
        response.status = HttpStatus.SWITCHING_PROTOCOLS;
        response.headers.add("Upgrade", "websocket");
        response.headers.add("Connection", "Upgrade");
        response.headers.add("Sec-WebSocket-Accept", createSecWebSocketAcceptHeader(key));
        response.flushHeaders();
    }
}

private string createSecWebSocketAcceptHeader(string key) {
    import std.digest.sha : sha1Of;
    import std.base64;
    ubyte[20] hash = sha1Of(key ~ "258EAFA5-E914-47DA-95CA-C5AB0DC85B11");
    return Base64.encode(hash);
}

unittest {
    string result = createSecWebSocketAcceptHeader("dGhlIHNhbXBsZSBub25jZQ==");
    assert(result == "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=");
}
