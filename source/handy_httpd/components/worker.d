/** 
 * This module contains the logic for each server worker, which involves
 * parsing and handling incoming requests.
 */
module handy_httpd.components.worker;

import std.socket;
import std.typecons;
import std.conv;
import core.thread;
import std.datetime;
import std.datetime.stopwatch;
import httparsed : MsgParser, initParser;
import slf4d;
import streams.primitives;
import streams.interfaces;
import streams.types.socket;
import streams.types.concat;
import streams.types.array;

import handy_httpd.server;
import handy_httpd.components.handler;
import handy_httpd.components.request;
import handy_httpd.components.response;
import handy_httpd.components.parse_utils;
import handy_httpd.util.range;

import std.stdio;

/** 
 * The server worker thread is a thread that processes incoming requests from
 * an `HttpServer`.
 */
class ServerWorkerThread : Thread {
    public const(int) id;
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
        auto log = getLogger();
        try {
            while (server.isReady) {
                // First try and get a socket to the client.
                log.debugF!"Worker-%d waiting for the next client."(this.id);
                Nullable!Socket nullableSocket = server.waitForNextClient();
                if (nullableSocket.isNull) {
                    continue;
                }
                Socket clientSocket = nullableSocket.get();

                auto inputStream = SocketInputStream(clientSocket);

                // Then try and parse their request and obtain a request context.
                Nullable!HttpRequestContext nullableCtx = receiveRequest(inputStream);
                if (nullableCtx.isNull) {
                    continue;
                }
                HttpRequestContext ctx = nullableCtx.get();

                // Then handle the request using the server's handler.
                log.infoF!"%s %s"(ctx.request.method, ctx.request.url);
                try {
                    this.server.getHandler.handle(ctx);
                    if (!ctx.response.isFlushed) {
                        ctx.response.flushHeaders();
                    }
                } catch (Exception e) {
                    log.debugF!"Encountered exception %s while handling request: %s"(e.classinfo.name, e.msg);
                    try {
                        this.server.getExceptionHandler.handle(ctx, e);
                    } catch (Exception e2) {
                        log.error("Exception occurred in the server's exception handler.", e2);
                    }
                }
                clientSocket.shutdown(SocketShutdown.BOTH);
                clientSocket.close();

                log.infoF!"%d %s"(ctx.response.status.code, ctx.response.status.text);

                // Reset the request parser so we're ready for the next request.
                requestParser.msg.reset();
                
                // Destroy the request context's allocated objects.
                destroy!(false)(ctx.request.inputStream);
                destroy!(false)(ctx.response.outputRange);
            }
        } catch (Exception e) {
            log.error(e);
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
    private Nullable!HttpRequestContext receiveRequest(S)(ref S inputStream) if (isByteInputStream!S) {
        auto log = getLogger();
        StreamResult initialReadResult = inputStream.readFromStream(this.receiveBuffer);
        if (initialReadResult.hasError) {
            log.errorF!"Worker-%d encountered socket receive failure: %s"(this.id, initialReadResult.error.message);
            return Nullable!HttpRequestContext.init;
        }
        log.debugF!"Worker-%d received %d bytes from the client."(this.id, initialReadResult.count);
        if (initialReadResult.count == 0) {
            return Nullable!HttpRequestContext.init; // Skip if we didn't receive valid data.
        }
        immutable ubyte[] data = receiveBuffer[0 .. initialReadResult.count].idup;

        // Prepare the request context by parsing the HttpRequest, and preparing the context.
        try {
            auto requestAndSize = handy_httpd.components.parse_utils.parseRequest(requestParser, cast(string) data);
            log.debugF!"Worker-%d parsed first %d bytes as the HTTP request."(this.id, requestAndSize[1]);
            return nullable(prepareRequestContext(requestAndSize[0], requestAndSize[1], initialReadResult.count, inputStream));
        } catch (Exception e) {
            log.warnF!"Worker-%d failed to parse HTTP request: %s"(this.id, e.msg);
            return Nullable!HttpRequestContext.init;
        }
    }

    /** 
     * Helper method to build the request context from the basic components
     * obtained from parsing a request.
     * Params:
     *   parsedRequest = The parsed request.
     *   bytesRead = The number of bytes read during request parsing.
     *   bytesReceived = The number of bytes initially received.
     *   socket = The socket that connected.
     * Returns: A request context that is ready handling.
     */
    private HttpRequestContext prepareRequestContext(S)(
        HttpRequest parsedRequest,
        size_t bytesRead,
        size_t bytesReceived,
        ref S inputStream
    ) if (isByteInputStream!S) {
        HttpRequestContext ctx = HttpRequestContext(
            parsedRequest,
            HttpResponse(),
            this.server,
            this
        );

        auto concatStream = concatInputStreamFor!(ArrayInputStream!ubyte, SocketInputStream)(
            arrayInputStreamFor(this.receiveBuffer[bytesRead .. bytesReceived]),
            inputStream
        );
        ctx.request.inputStream = inputStreamWrapperFor(concatStream);
        // ctx.response.outputRange = new SocketOutputRange(socket);
        foreach (headerName, headerValue; this.server.config.defaultHeaders) {
            ctx.response.addHeader(headerName, headerValue);
        }
        return ctx;
    }

    /** 
     * Gets a pointer to this worker's internal pre-allocated receive buffer.
     * Returns: A pointer to the worker's receive buffer.
     */
    public ubyte[]* getReceiveBuffer() {
        return &receiveBuffer;
    }

    /** 
     * Gets the server that this worker was created for.
     * Returns: The server.
     */
    public HttpServer getServer() {
        return server;
    }
}