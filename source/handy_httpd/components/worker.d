/** 
 * This module contains the logic for each server worker, which involves
 * parsing and handling incoming requests.
 */
module handy_httpd.components.worker;

import std.socket;
import std.typecons : Nullable, nullable;
import std.conv : to;
import core.thread;
import core.atomic : atomicStore, atomicLoad;
import httparsed : MsgParser, initParser;
import slf4d;
import streams.primitives;
import streams.interfaces;
import streams.types.socket;
import streams.types.concat;
import streams.types.array;
import streams.types.buffered;

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
    /**
     * The id of this worker thread.
     */
    public const(int) id;

    /**
     * The reusable request parser that will be called for each incoming request.
     */
    private MsgParser!Msg requestParser = initParser!Msg();

    /**
     * A pre-allocated buffer for receiving data from the client.
     */
    private ubyte[] receiveBuffer;

    /**
     * The server that this worker belongs to.
     */
    private HttpServer server;

    /**
     * A preconfigured SLF4D logger that uses the worker's id in its label.
     */
    private Logger logger;

    /**
     * A shared indicator of whether this worker is currently handling a request.
     */
    private shared bool busy = false;

    /** 
     * Constructs this worker thread for the given server, with the given id.
     * Params:
     *   server = The server that this thread belongs to.
     *   id = The thread's id.
     */
    this(HttpServer server, int id) {
        super(&run);
        super.name("handy_httpd_worker-" ~ id.to!string);
        this.id = id;
        this.receiveBuffer = new ubyte[server.config.receiveBufferSize];
        this.server = server;
        this.logger = getLogger(super.name());
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
            try {
                // First try and get a socket to the client.
                Nullable!Socket nullableSocket = server.waitForNextClient();
                if (nullableSocket.isNull || !nullableSocket.get().isAlive()) {
                    if (!nullableSocket.isNull) nullableSocket.get().close();
                    continue;
                }
                atomicStore(this.busy, true); // Since we got a legit client, mark this worker as busy.
                scope(exit) {
                    atomicStore(this.busy, false);
                }
                Socket clientSocket = nullableSocket.get();
                this.logger.debugF!"Got client socket: %s"(clientSocket.remoteAddress());

                SocketInputStream inputStream = SocketInputStream(clientSocket);
                SocketOutputStream outputStream = SocketOutputStream(clientSocket);

                // Then try and parse their request and obtain a request context.
                Nullable!HttpRequestContext nullableCtx = receiveRequest(
                    &inputStream, &outputStream, clientSocket.remoteAddress, clientSocket
                );
                if (nullableCtx.isNull) {
                    this.logger.debug_("Skipping this request because we couldn't get a context.");
                    continue;
                }
                HttpRequestContext ctx = nullableCtx.get();

                // Then handle the request using the server's handler.
                this.logger.infoF!"Request: Method=%s, URL=\"%s\""(ctx.request.method, ctx.request.url);
                try {
                    this.server.getHandler.handle(ctx);
                    if (!ctx.response.isFlushed) {
                        ctx.response.flushHeaders();
                    }
                } catch (Exception e) {
                    this.logger.debugF!"Encountered exception %s while handling request: %s"(e.classinfo.name, e.msg);
                    try {
                        this.server.getExceptionHandler.handle(ctx, e);
                    } catch (Exception e2) {
                        this.logger.error("Exception occurred in the server's exception handler.", e2);
                    }
                }
                // Only close the socket if we're not switching protocols.
                if (ctx.response.status != HttpStatus.SWITCHING_PROTOCOLS) {
                    clientSocket.shutdown(SocketShutdown.BOTH);
                    clientSocket.close();
                    // Destroy the request context's allocated objects.
                    destroy!(false)(ctx.request.inputStream);
                    destroy!(false)(ctx.response.outputStream);
                    destroy!(false)(ctx.metadata);
                } else {
                    this.logger.debug_("Keeping socket alive due to SWITCHING_PROTOCOLS status.");
                }

                this.logger.infoF!"Response: Status=%d %s"(ctx.response.status.code, ctx.response.status.text);

                // Reset the request parser so we're ready for the next request.
                requestParser.msg.reset();
            } catch (Exception e) {
                logger.error("An unhandled exception occurred in this worker's `run` method.", e);
            }
        }
    }

    /** 
     * Attempts to receive an HTTP request from the given socket.
     * Params:
     *   inputStream = The input stream to read the request from.
     *   outputStream = The output stream to write response content to.
     *   remoteAddress = The client's address.
     *   clientSocket = The underlying socket to the client.
     * Returns: A nullable request context, which if present, can be used to
     * further handle the request. If null, no further action should be taken
     * beyond closing the socket.
     */
    private Nullable!HttpRequestContext receiveRequest(StreamIn, StreamOut)(
        StreamIn inputStream,
        StreamOut outputStream,
        Address remoteAddress,
        Socket clientSocket
    ) if (isByteInputStream!StreamIn && isByteOutputStream!StreamOut) {
        this.logger.trace("Reading the initial request into the receive buffer.");
        StreamResult initialReadResult = inputStream.readFromStream(this.receiveBuffer);
        if (initialReadResult.hasError) {
            this.logger.errorF!"Encountered socket receive failure: %s, lastSocketError = %s"(
                initialReadResult.error.message,
                lastSocketError()
            );
            return Nullable!HttpRequestContext.init;
        }
        this.logger.debugF!"Received %d bytes from the client."(initialReadResult.count);
        if (initialReadResult.count == 0) {
            return Nullable!HttpRequestContext.init; // Skip if we didn't receive valid data.
        }
        immutable ubyte[] data = receiveBuffer[0 .. initialReadResult.count].idup;

        // Prepare the request context by parsing the HttpRequest, and preparing the context.
        try {
            auto requestAndSize = handy_httpd.components.parse_utils.parseRequest(requestParser, cast(string) data);
            this.logger.debugF!"Parsed first %d bytes as the HTTP request."(requestAndSize[1]);
            return nullable(prepareRequestContext(
                requestAndSize[0],
                requestAndSize[1],
                initialReadResult.count,
                inputStream,
                outputStream,
                remoteAddress,
                clientSocket
            ));
        } catch (Exception e) {
            this.logger.warnF!"Failed to parse HTTP request: %s"(e.msg);
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
     *   inputStream = The stream to read the request from.
     *   outputStream = The stream to write response content to.
     *   remoteAddress = The client's address.
     *   clientSocket = The underlying socket to the client.
     * Returns: A request context that is ready for handling.
     */
    private HttpRequestContext prepareRequestContext(StreamIn, StreamOut)(
        HttpRequest parsedRequest,
        size_t bytesRead,
        size_t bytesReceived,
        StreamIn inputStream,
        StreamOut outputStream,
        Address remoteAddress,
        Socket clientSocket
    ) if (isByteInputStream!StreamIn && isByteOutputStream!StreamOut) {
        HttpRequestContext ctx = HttpRequestContext(
            parsedRequest,
            HttpResponse(),
            this.server,
            this
        );
        ctx.request.receiveBuffer = this.receiveBuffer;
        if (bytesReceived > bytesRead) {
            ctx.request.inputStream = inputStreamObjectFor(concatInputStreamFor(
                arrayInputStreamFor(this.receiveBuffer[bytesRead .. bytesReceived]),
                bufferedInputStreamFor(inputStream)
            ));
        } else {
            ctx.request.inputStream = inputStreamObjectFor(bufferedInputStreamFor(inputStream));
        }
        ctx.request.remoteAddress = remoteAddress;
        ctx.clientSocket = clientSocket;
        ctx.response.outputStream = outputStreamObjectFor(outputStream);
        this.logger.traceF!"Preparing HttpRequestContext using input stream\n%s\nand output stream\n%s"(
            ctx.request.inputStream,
            ctx.response.outputStream
        );
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

    /**
     * Tells whether this worker is currently busy handling a request.
     * Returns: True if this worker is handling a request, or false otherwise.
     */
    public bool isBusy() {
        return atomicLoad(this.busy);
    }
}