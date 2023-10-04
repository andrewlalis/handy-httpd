/**
 * Defines components relating to how websocket messages and initial HTTP
 * requests are handled.
 */
module handy_httpd.components.websocket.handler;

import handy_httpd.components.handler : HttpRequestHandler, HttpRequestContext;

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
 * An enumeration of possible closing status codes for websocket connections,
 * as per https://datatracker.ietf.org/doc/html/rfc6455#section-7.4
 */
enum WebSocketCloseStatusCode : ushort {
    NORMAL = 1000,
    GOING_AWAY = 1001,
    PROTOCOL_ERROR = 1002,
    UNACCEPTABLE_DATA = 1003,
    NO_CODE = 1005,
    CLOSED_ABNORMALLY = 1006,
    INCONSISTENT_DATA = 1007,
    POLICY_VIOLATION = 1008,
    MESSAGE_TOO_BIG = 1009,
    EXTENSION_NEGOTIATION_FAILURE = 1010,
    UNEXPECTED_CONDITION = 1011,
    TLS_HANDSHAKE_FAILURE = 1015
}

/**
 * An abstract class that you should extend to define logic for handling
 * websocket messages and events. Create a new class that inherits from this
 * one, and overrides any "on..." methods.
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
    import std.socket : Socket;
    import handy_httpd.components.websocket.frame;
    import streams : SocketOutputStream, byteArrayOutputStream, dataOutputStreamFor;

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
        sendWebSocketFrame(
            SocketOutputStream(this.socket),
            WebSocketFrame(true, WebSocketFrameOpcode.TEXT_FRAME, cast(ubyte[]) text)
        );
    }

    /**
     * Sends a binary message to the connected client.
     * Params:
     *   bytes = The binary data to send.
     */
    void sendBinaryMessage(ubyte[] bytes) {
        sendWebSocketFrame(
            SocketOutputStream(this.socket),
            WebSocketFrame(true, WebSocketFrameOpcode.BINARY_FRAME, bytes)
        );
    }

    /**
     * Sends a close message to the client, indicating that we'll be closing
     * the connection.
     * Params:
     *   status = The status code for closing.
     *   message = A message explaining why we're closing. Length must be <= 123.
     */
    void sendCloseMessage(WebSocketCloseStatusCode status, string message) {
        auto arrayOut = byteArrayOutputStream();
        auto dOut = dataOutputStreamFor(&arrayOut);
        dOut.writeToStream!ushort(status);
        if (message !is null && message.length > 0) {
            if (message.length > 123) {
                throw new WebSocketException("Close message is too long! Maximum of 123 bytes allowed.");
            }
            arrayOut.writeToStream(cast(ubyte[]) message);
        }
        sendWebSocketFrame(
            SocketOutputStream(this.socket),
            WebSocketFrame(true, WebSocketFrameOpcode.CONNECTION_CLOSE, arrayOut.toArray())
        );
    }
}

/**
 * A special HttpRequestHandler implementation that exclusively handles
 * websocket connection handshakes.
 */
class WebSocketHandler : HttpRequestHandler {
    import handy_httpd.components.request : Method;
    import handy_httpd.components.response : HttpStatus;

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
    void handle(ref HttpRequestContext ctx) {
        if (!this.verifyRequest(ctx)) return;
        this.sendSwitchingProtocolsResponse(ctx);
        ctx.server.getWebSocketManager().registerConnection(ctx.clientSocket, this.messageHandler);
    }

    /**
     * Verifies a websocket request.
     * Params:
     *   ctx = The request context to verify.
     * Returns: True if the request is valid can a websocket connection can be
     * created, or false if we should reject. A response message will already
     * be written in that case.
     */
    private bool verifyRequest(ref HttpRequestContext ctx) {
        string origin = ctx.request.getHeader("origin");
        // TODO: Verify correct origin.
        if (ctx.request.method != Method.GET) {
            ctx.response.setStatus(HttpStatus.METHOD_NOT_ALLOWED);
            ctx.response.writeBodyString("Only GET requests are allowed.");
            return false;
        }
        string key = ctx.request.getHeader("Sec-WebSocket-Key");
        if (key is null) {
            ctx.response.setStatus(HttpStatus.BAD_REQUEST);
            ctx.response.writeBodyString("Missing Sec-WebSocket-Key header.");
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
    private void sendSwitchingProtocolsResponse(ref HttpRequestContext ctx) {
        string key = ctx.request.getHeader("Sec-WebSocket-Key");
        ctx.response.setStatus(HttpStatus.SWITCHING_PROTOCOLS);
        ctx.response.addHeader("Upgrade", "websocket");
        ctx.response.addHeader("Connection", "Upgrade");
        ctx.response.addHeader("Sec-WebSocket-Accept", createSecWebSocketAcceptHeader(key));
        ctx.response.flushHeaders();
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
