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
import handy_httpd.components.response;
import handy_httpd.components.parse_utils;

/** 
 * The server worker thread is a thread that processes incoming requests from
 * an `HttpServer`.
 */
class ServerWorkerThread : Thread {
    private MsgParser!Msg requestParser = initParser!Msg();
    private char[] receiveBuffer;
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
        this.receiveBuffer = new char[server.config.receiveBufferSize];
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
            this.server.getLogger.infoFV!"<- %s %s"(ctx.request.method, ctx.request.url);
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
                this.server.getLogger.infoFV!"Client %s closed the connection before a request was sent."(
                    clientSocket.remoteAddress
                );
            } else if (received == Socket.ERROR) {
                this.server.getLogger.infoFV!"Socket receive() failed for client at %s."(clientSocket.remoteAddress);
            }
            return result; // Skip if we didn't receive valid data.
        }
        string data = receiveBuffer[0..received].idup;

        // Prepare the request context by parsing the HttpRequest, and preparing a default response.
        HttpRequestContext ctx = HttpRequestContext(
            parseRequest(requestParser, data),
            HttpResponse().setStatus(200).setStatusText("OK")
        );
        ctx.server = this.server;
        ctx.clientSocket = clientSocket;
        ctx.response.clientSocket = clientSocket;
        foreach (headerName, headerValue; this.server.config.defaultHeaders) {
            ctx.response.addHeader(headerName, headerValue);
        }
        result = ctx;
        
        // Use the Content-Length header to try and continue reading the rest of the body.
        const(string*) providedContentLength = "Content-Length" in ctx.request.headers;
        if (providedContentLength !is null) {
            try {
                size_t contentLength = (*providedContentLength).to!size_t;
                size_t receivedTotal = ctx.request.bodyContent.length;
                while (receivedTotal < contentLength && received > 0) {
                    received = clientSocket.receive(receiveBuffer);
                    receivedTotal += received;
                    ctx.request.bodyContent ~= receiveBuffer[0..received].idup;
                }
            } catch(ConvException e) {
                this.server.getLogger.infoFV!"Content-Length is not a number: %s"(e.msg);
            }
        }

        return result;
    }
}