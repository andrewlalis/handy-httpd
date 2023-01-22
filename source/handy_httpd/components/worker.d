/** 
 * This module contains the logic for each server worker, which involves
 * parsing and handling incoming requests.
 */
module handy_httpd.components.worker;

import std.socket;
import std.typecons;
import std.conv;
import core.thread;
import httparsed : MsgParser, initParser;

import handy_httpd.server;
import handy_httpd.components.handler;
import handy_httpd.components.request;
import handy_httpd.components.response;
import handy_httpd.components.parse_utils;

/** 
 * The server worker thread is a thread that processes incoming requests from
 * an `HttpServer`.
 */
class ServerWorkerThread : Thread {
    private const(int) id;
    private MsgParser!Msg requestParser = initParser!Msg();
    private ubyte[] receiveBuffer;
    private HttpServer server;

    /** 
     * Constructs this worker thread for the given server, with the given id.
     * Params:
     *   server = The server that this thread belongs to.
     *   id = The thread's id.
     */
    this(HttpServer server, int id) {
        super(&run);
        super.name("handy-httpd_worker-" ~ id.to!string);
        this.id = id;
        this.receiveBuffer = new ubyte[server.config.receiveBufferSize];
        this.server = server;
    }

    /** 
     * Runs the worker thread. This will run continuously until the server
     * stops. The worker will do the following:
     * 
     * 1. Wait for the next available client.
     * 2. Parse the HTTP request from the client.
     * 3. Handle the request using the server's handler.
     */
    private void run() {
        while (server.isReady) {
            // First try and get a socket to the client.
            Nullable!Socket nullableSocket = server.waitForNextClient();
            if (nullableSocket.isNull) continue;
            Socket clientSocket = nullableSocket.get();

            // Then try and parse their request and obtain a request context.
            Nullable!HttpRequestContext nullableCtx = receiveRequest(clientSocket);
            if (nullableCtx.isNull) continue;
            HttpRequestContext ctx = nullableCtx.get();

            // Then handle the request using the server's handler.
            this.server.getLogger.infoFV!"[%s] <- %s %s"(this.name, ctx.request.method, ctx.request.url);
            try {
                this.server.getHandler.handle(ctx);
            } catch (Exception e) {
                this.server.getExceptionHandler.handle(ctx, e);
            }
            clientSocket.close();

            // Reset the request parser so we're ready for the next request.
            requestParser.msg.reset();
        }
    }

    /** 
     * Attempts to receive an HTTP request from the given socket.
     * Params:
     *   clientSocket = The socket to receive from.
     * Returns: A nullable request context, which if present, can be used to
     * further handle the request. If null, no further action should be taken
     * beyond closing the socket.
     */
    private Nullable!HttpRequestContext receiveRequest(Socket clientSocket) {
        Nullable!HttpRequestContext result;
        size_t received = clientSocket.receive(receiveBuffer);
        if (received == 0 || received == Socket.ERROR) {
            if (received == 0) {
                this.server.getLogger.infoFV!"[%s] Client %s closed the connection before a request was sent."(
                    this.name,
                    clientSocket.remoteAddress
                );
            } else if (received == Socket.ERROR) {
                this.server.getLogger.infoFV!"[%s] Socket receive() failed."(this.name);
            }
            return result; // Skip if we didn't receive valid data.
        }
        immutable ubyte[] data = receiveBuffer[0..received].idup;

        // Prepare the request context by parsing the HttpRequest, and preparing a default response.
        try {
            auto requestAndSize = handy_httpd.components.parse_utils.parseRequest(requestParser, cast(string) data);
            HttpRequest request = requestAndSize[0];
            int size = requestAndSize[1];
            request.clientSocket = clientSocket;
            request.receiveBuffer = getReceiveBuffer();
            request.receiveBufferOffset = size;
            request.receivedByteCount = received;
            HttpRequestContext ctx = HttpRequestContext(
                request,
                HttpResponse(),
                clientSocket,
                this.server,
                this
            );
            ctx.response.clientSocket = clientSocket;
            foreach (headerName, headerValue; this.server.config.defaultHeaders) {
                ctx.response.addHeader(headerName, headerValue);
            }
            result = ctx;
            return result;
        } catch (Exception e) {
            this.server.getLogger.infoFV!"[%s] Failed to parse HTTP request: %s"(this.name, e.msg);
            clientSocket.close();
            return result;
        }
    }

    /** 
     * Gets this worker's id.
     * Returns: The worker id.
     */
    public int getId() {
        return id;
    }

    /** 
     * Gets a pointer to this worker's internal pre-allocated receive buffer.
     * Returns: A pointer to the worker's receive buffer.
     */
    public ubyte[]* getReceiveBuffer() {
        return &receiveBuffer;
    }
}