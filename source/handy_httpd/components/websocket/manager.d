/**
 * This module defines the websocket manager and associated elements that are
 * responsible for managing all connected websockets.
 */
module handy_httpd.components.websocket.manager;

import core.thread.osthread : Thread;
import streams;
import slf4d;

/**
 * An event-loop based websocket manager thread that handles incoming messages
 * and passes them off to their connection's message handler. This manager is
 * enabled by setting the configuration option `enableWebSockets` to `true`.
 *
 * This manager controls the list of connected websocket clients, so in
 * practice, you will most often use the manager for its `broadcast` methods to
 * send out messages to all clients. You can get an instance of this manager
 * from a request context like so: `ctx.server.getWebSocketManager()`
 */
class WebSocketManager : Thread {
    import std.uuid : UUID;
    import std.socket : Socket, SocketSet, SocketShutdown;
    import core.sync.rwmutex : ReadWriteMutex;
    import handy_httpd.components.websocket.handler;
    import handy_httpd.components.websocket.frame;

    private WebSocketConnection[UUID] connections;
    private ReadWriteMutex connectionsMutex;
    private SocketSet readableSocketSet;
    private WebSocketFrame[UUID] continuationFrames;
    private shared bool running = false;

    /**
     * Constructs a new manager with an initially empty socket set.
     */
    this() {
        super(&this.run);
        this.connectionsMutex = new ReadWriteMutex();
        this.readableSocketSet = new SocketSet();
    }

    /**
     * Registers a new websocket connection to this manager, and begins
     * listening for messages to pass on to the given handler.
     * Params:
     *   socket = The socket that's connected.
     *   handler = The handler to handle any websocket messages.
     */
    void registerConnection(Socket socket, WebSocketMessageHandler handler) {
        socket.blocking(false);
        auto conn = new WebSocketConnection(socket, handler);
        synchronized(this.connectionsMutex.writer) {
            this.connections[conn.id] = conn;
        }
        conn.getMessageHandler().onConnectionEstablished(conn);
    }

    /**
     * Removes an existing websocket connection from this manager and closes
     * the socket.
     * Params:
     *   conn = The connection to remove.
     */
    void deregisterConnection(WebSocketConnection conn) {
        synchronized(this.connectionsMutex.writer) {
            this.connections.remove(conn.id);
        }
        conn.close();
    }

    /**
     * Broadcasts a binary message to all connected clients.
     * Params:
     *   bytes = The content to send.
     */
    void broadcast(ubyte[] bytes) {
        synchronized(this.connectionsMutex.reader) {
            foreach (id, conn; this.connections) {
                try {
                    conn.sendBinaryMessage(bytes);
                } catch (WebSocketException e) {
                    warn("Failed to broadcast to client " ~ id.toString() ~ ".", e);
                }
            }
        }
    }

    /**
     * Broadcasts a text message to all connected clients.
     * Params:
     *   text = The text to send.
     */
    void broadcast(string text) {
        synchronized(this.connectionsMutex.reader) {
            foreach (id, conn; this.connections) {
                try {
                    conn.sendTextMessage(text);
                } catch (WebSocketException e) {
                    warn("Failed to broadcast to client " ~ id.toString() ~ ".", e);
                }
            }
        }
    }

    /**
     * The main method of the manager thread, which repeatedly checks for
     * sockets to read from.
     */
    private void run() {
        import core.atomic : atomicStore, atomicLoad;
        import std.datetime : msecs;
        atomicStore(this.running, true);
        debug_("WebSocket manager thread started.");
        while (atomicLoad(this.running)) {
            uint socketCount = 0;
            synchronized(this.connectionsMutex.writer) {
                foreach (id, conn; this.connections) {
                    if (conn.getSocket().isAlive()) {
                        this.readableSocketSet.add(conn.getSocket());
                        socketCount++;
                    } else {
                        debugF!"Connection has died: %s"(conn.id);
                        this.connections.remove(conn.id);
                        conn.getMessageHandler().onConnectionClosed(conn);
                    }
                }
            }

            // If there are no connections at all to read from, just wait and try again.
            if (socketCount == 0) {
                Thread.sleep(msecs(1));
                continue;
            }
            
            int count = Socket.select(this.readableSocketSet, null, null, msecs(100));
            if (count == -1) {
                warn("Interrupted while waiting for a socket status update.");
            } else if (count > 0) {
                synchronized(this.connectionsMutex.writer) {
                    foreach (id, conn; this.connections) {
                        if (this.readableSocketSet.isSet(conn.getSocket())) {
                            try {
                                this.handleIncomingMessage(conn);
                            } catch (WebSocketException wex) {
                                error("Failed to handle incoming message.", wex);
                            } catch (Exception e) {
                                error("Exception occurred while handling message.", e);
                            } catch (Throwable t) {
                                errorF!
                                    "A fatal error occurred while handling message: %s, file %s, line %d\nInfo:\n%s"
                                (t.msg, t.file, t.line, t.info);
                                error("The websocket manager thread will now be killed.");
                                throw t;
                            }
                        }
                    }
                }
            }
            this.readableSocketSet.reset();
        }
        debug_("WebSocket manager thread stopped.");
        // After stopping, we should try and send a close frame to each connection.
        WebSocketConnection[] connList;
        synchronized(this.connectionsMutex.writer) {
            connList = this.connections.values();
            this.connections.clear();
        }
        foreach (conn; connList) {
            this.deregisterConnection(conn);
        }
    }

    /**
     * Stops the manager thread.
     */
    void stop() {
        import core.atomic : atomicStore;
        atomicStore(this.running, false);
    }

    /**
     * Reads and handles any incoming websocket frame from the given connection.
     * Params:
     *   conn = The connection to receive a websocket frame from.
     */
    private void handleIncomingMessage(WebSocketConnection conn) {
        SocketInputStream sIn = SocketInputStream(conn.getSocket());
        WebSocketFrame frame;
        try {
            frame = receiveWebSocketFrame(sIn);
        } catch (WebSocketException e) {
            warn("Failed to receive a websocket frame from connection. Closing the connection. Error: " ~ e.msg);
            this.connections.remove(conn.id);
            conn.close();
            return;
        }
        debugF!"Received websocket frame from connection %s @ %s: %s, payload length = %d"(
            conn.id,
            conn.getSocket().remoteAddress(),
            frame.opcode,
            frame.payload.length
        );
        switch (frame.opcode) {
            case WebSocketFrameOpcode.CONNECTION_CLOSE:
                this.handleClientClose(frame, conn);
                break;
            case WebSocketFrameOpcode.PING:
                sendWebSocketPongFrame(SocketOutputStream(conn.getSocket()), frame.payload);
                break;
            case WebSocketFrameOpcode.TEXT_FRAME:
            case WebSocketFrameOpcode.BINARY_FRAME:
                this.handleClientDataFrame(frame, conn);
                break;
            case WebSocketFrameOpcode.CONTINUATION:
                this.handleFrameContinuation(frame, conn);
                break;
            default:
                break;
        }
    }

    /**
     * Handles a client's "close" control message by echoing the data frame
     * back to the client, closing the underlying socket connection, and
     * notifying the message handler of the event.
     * Params:
     *   closeFrame = The close frame sent by the client.
     *   conn = The connection that received the close frame.
     */
    private void handleClientClose(WebSocketFrame closeFrame, ref WebSocketConnection conn) {
        WebSocketCloseMessage msg = WebSocketCloseMessage(conn, WebSocketCloseStatusCode.NO_CODE, null);
        conn.getMessageHandler().onCloseMessage(msg);
        if (closeFrame.payload.length >= 2) {
            union U { ushort value; ubyte[2] bytes; }
            U u;
            u.bytes = closeFrame.payload[0 .. 2];
            msg.statusCode = u.value;
            if (closeFrame.payload.length > 2) {
                msg.message = cast(string) closeFrame.payload[2 .. $];
            }
        }
        try {
            sendWebSocketFrame(SocketOutputStream(conn.getSocket()), closeFrame);
        } catch (WebSocketException e) {
            // Ignore any failure in sending an echo response back.
        }
        conn.getSocket().shutdown(SocketShutdown.BOTH);
        conn.getSocket().close();
        conn.getMessageHandler().onConnectionClosed(conn);
    }

    /**
     * Handles a client's data frame (text or binary) by checking if it's a
     * single fragment, and if so, passing off handling to the message handler.
     * Otherwise, saves the frame as the current "continued" frame so that we
     * can append to it in `handleFrameContinuation`.
     * Params:
     *   frame = The frame that the client sent.
     *   conn = The connection that received the data frame.
     */
    private void handleClientDataFrame(WebSocketFrame frame, ref WebSocketConnection conn) {
        bool isText = frame.opcode == WebSocketFrameOpcode.TEXT_FRAME;
        if (frame.finalFragment) {
            if (isText) {
                conn.getMessageHandler().onTextMessage(WebSocketTextMessage(conn, cast(string) frame.payload));
            } else {
                conn.getMessageHandler().onBinaryMessage(WebSocketBinaryMessage(conn, frame.payload));
            }
        } else {
            this.continuationFrames[conn.id] = frame;
        }
    }

    /**
     * Handles a client's continuation frame, which is an additional data frame
     * that appends content to a previous frame's payload to form a larger
     * message.
     * Params:
     *   frame = The frame that was received.
     *   conn = The connection that received the frame.
     */
    private void handleFrameContinuation(WebSocketFrame frame, ref WebSocketConnection conn) {
        WebSocketFrame* continuedFrame = conn.id in this.continuationFrames;
        if (continuedFrame is null) {
            return; // Ignore a continuation frame if we aren't yet tracking an initial frame for a connection.
        }
        continuedFrame.payload ~= frame.payload;
        if (frame.finalFragment) {
            bool isText = continuedFrame.opcode == WebSocketFrameOpcode.TEXT_FRAME;
            if (isText) {
                conn.getMessageHandler().onTextMessage(WebSocketTextMessage(conn, cast(string) continuedFrame.payload));
            } else {
                conn.getMessageHandler().onBinaryMessage(WebSocketBinaryMessage(conn, continuedFrame.payload));
            }
            // Remove the continuation frame now that we've received the final frame.
            this.continuationFrames.remove(conn.id);
        }
    }
}
