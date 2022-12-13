/** 
 * Contains the core HTTP server components.
 */
module handy_httpd.server;

import std.socket;
import std.regex;
import std.conv : to, ConvException;
import std.container.dlist : DList;
import core.sync.semaphore : Semaphore;
import core.atomic : atomicLoad;
import core.thread.threadgroup : ThreadGroup;

import handy_httpd.request;
import handy_httpd.response;
import handy_httpd.handler;
import handy_httpd.server_config;
import handy_httpd.parse_utils : parseRequest, Msg;
import handy_httpd.logger;

import httparsed : MsgParser, initParser;

/** 
 * A simple HTTP server that accepts requests on a given port and address, and
 * lets a configured HttpRequestHandler produce a response, to send back to the
 * client.
 */
class HttpServer {
    /** 
     * The server's configuration values.
     */
    public ServerConfig config;

    /** 
     * The address to which this server is bound.
     */
    private Address address;

    /** 
     * The handler that all requests will be delegated to.
     */
    private HttpRequestHandler handler;

    /** 
     * An exception handler to use when an exception occurs.
     */
    private ServerExceptionHandler exceptionHandler;

    /** 
     * Internal flag that indicates when we're ready to accept connections.
     */
    private shared bool ready = false;

    /** 
     * The server socket that accepts connections.
     */
    private Socket serverSocket = null;

    /** 
     * A semaphore that's used to coordinate worker threads so that they can
     * each take from the request queue.
     */
    private Semaphore requestSemaphore;

    /** 
     * The queue of requests to process, from which worker threads will pull.
     */
    private DList!Socket requestQueue;

    /** 
     * The group of worker threads that will process requests.
     */
    private ThreadGroup workerThreadGroup;

    /** 
     * The server's logger.
     */
    private ServerLogger log;

    /** 
     * Constructs a new server using the supplied handler to handle all
     * incoming requests.
     * Params:
     *   handler = The handler to handle all requests.
     *   config = The server configuration.
     */
    this(
        HttpRequestHandler handler = noOpHandler(),
        ServerConfig config = ServerConfig.defaultValues
    ) {
        this.config = config;
        this.address = parseAddress(config.hostname, config.port);
        this.handler = handler;
        this.log = ServerLogger(&this.config);
        this.exceptionHandler = new BasicServerExceptionHandler();
    }

    /** 
     * Constructs a new server using the supplied handler function to handle
     * all incoming requests.
     * Params:
     *   handlerFunc = The function to use to handle requests.
     *   config = The server configuration.
     */
    this(
        void function(ref HttpRequestContext) handlerFunc,
        ServerConfig config = ServerConfig.defaultValues
    ) {
        this(toHandler(handlerFunc), config);
    }

    /** 
     * Starts the server on the calling thread, so that it will begin accepting
     * HTTP requests. Once the server is able to accept requests, `isReady()`
     * will return true, and will remain true until the server is stopped by
     * calling `stop()`.
     */
    public void start() {
        this.serverSocket = new TcpSocket();
        if (this.config.reuseAddress) {
            this.serverSocket.setOption(SocketOptionLevel.SOCKET, SocketOption.REUSEADDR, 1);
        }
        foreach (socketConfigFunction; this.config.preBindCallbacks) {
            socketConfigFunction(this.serverSocket);
        }
        this.serverSocket.bind(this.address);
        log.infoFV!"Bound to address %s"(this.address);
        this.serverSocket.listen(this.config.connectionQueueSize);
        initWorkerThreads();
        this.ready = true;

        log.infoV("Now accepting connections.");
        while (this.serverSocket.isAlive()) {
            Socket clientSocket = this.serverSocket.accept();
            this.requestQueue.insertBack(clientSocket);
            this.requestSemaphore.notify();
        }
        this.ready = false;
        
        shutdownWorkerThreads();
    }

    /** 
     * Shuts down the server by closing the server socket, if possible. This
     * will block until all pending requests have been fulfilled.
     */
    public void stop() {
        log.infoV("Stopping the server.");
        if (this.serverSocket !is null) {
            this.serverSocket.close();
        }
    }

    /** 
     * Tells whether the server is ready to receive requests.
     * Returns: Whether the server is ready to receive requests.
     */
    public bool isReady() {
        return this.ready;
    }

    /** 
     * Spawns all worker threads in a new thread group, and initializes the
     * semaphore that they will use to be notified of work to do.
     */
    private void initWorkerThreads() {
        this.requestSemaphore = new Semaphore();
        this.workerThreadGroup = new ThreadGroup();
        for (int i = 0; i < this.config.workerPoolSize; i++) {
            this.workerThreadGroup.create(&workerThreadFunction);
        }
    }

    /** 
     * Shuts down all worker threads by sending one final semaphore notification
     * to all of them.
     */
    private void shutdownWorkerThreads() {
        for (int i = 0; i < this.config.workerPoolSize; i++) {
            this.requestSemaphore.notify();
        }
        this.workerThreadGroup.joinAll();
    }

    /** 
     * Worker function that runs for all worker threads that process incoming
     * requests. Workers will wait for the requestSemaphore to be notified so
     * that they can process a request. The worker will stay alive as long as
     * this server is set as ready.
     */
    private void workerThreadFunction() {
        MsgParser!Msg requestParser = initParser!Msg();
        char[] receiveBuffer = new char[this.config.receiveBufferSize];
        while (atomicLoad(this.ready)) {
            this.requestSemaphore.wait();
            if (!this.requestQueue.empty) {
                Socket clientSocket = this.requestQueue.removeAny();
                size_t received = clientSocket.receive(receiveBuffer);
                if (received == 0 || received == Socket.ERROR) {
                    continue; // Skip if we didn't receive valid data.
                }
                string data = receiveBuffer[0..received].idup;
                requestParser.msg.reset();

                // Prepare the request context by parsing the HttpRequest, and preparing a default response.
                HttpRequestContext ctx = HttpRequestContext(
                    parseRequest(requestParser, data),
                    HttpResponse().setStatus(200).setStatusText("OK")
                );
                ctx.request.server = this;
                ctx.request.clientSocket = clientSocket;
                ctx.response.clientSocket = clientSocket;
                foreach (headerName, headerValue; this.config.defaultHeaders) {
                    ctx.response.addHeader(headerName, headerValue);
                }
                
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
                        log.infoFV!"Content-Length is not a number: %s"(e.msg);
                    }
                }

                log.infoFV!"<- %s %s"(ctx.request.method, ctx.request.url);
                try {
                    this.handler.handle(ctx);
                } catch (Exception e) {
                    this.exceptionHandler.handle(ctx, e);
                }
                clientSocket.close();
            }
        }
    }

    /** 
     * Gets the server's logger.
     * Returns: The server's logger.
     */
    ServerLogger getLogger() {
        return log;
    }
}
