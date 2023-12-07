/** 
 * Contains the core HTTP server implementation.
 */
module handy_httpd.server;

import std.socket;
import std.conv : to, ConvException;
import std.container.dlist : DList;
import std.typecons : Nullable;
import core.sync.semaphore : Semaphore;
import core.sync.exception;
import core.sync.rwmutex;
import core.atomic;
import core.thread : Thread;
import core.thread.threadgroup : ThreadGroup;

import handy_httpd.components.request;
import handy_httpd.components.response;
import handy_httpd.components.handler;
import handy_httpd.components.config;
import handy_httpd.components.parse_utils : parseRequest, Msg;
import handy_httpd.components.worker;
import handy_httpd.components.request_queue;
import handy_httpd.components.worker_pool;
import handy_httpd.components.websocket;

import httparsed : MsgParser, initParser;
import slf4d;

/** 
 * A simple HTTP server that accepts requests on a given port and address, and
 * lets a configured HttpRequestHandler produce a response, to send back to the
 * client.
 */
class HttpServer {
    /** 
     * The server's configuration values.
     */
    public const ServerConfig config;

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

    private RequestQueue requestQueue2;

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
     * A mutex for controlling multi-threaded access to the request queue. This
     * is primarily used when adding Sockets to the request queue, and removing
     * them when a worker has been notified.
     */
    private ReadWriteMutex requestQueueMutex;

    /** 
     * The managed thread pool containing workers to handle requests.
     */
    private WorkerPool workerPool;

    /**
     * A manager thread for handling all websocket connections.
     */
    private WebSocketManager websocketManager;

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
        this.requestSemaphore = new Semaphore();
        this.requestQueueMutex = new ReadWriteMutex();
        this.exceptionHandler = new BasicServerExceptionHandler();
        this.workerPool = new WorkerPool(this);
        if (config.enableWebSockets) {
            this.websocketManager = new WebSocketManager();
        }
    }

    /** 
     * Constructs a new server using the supplied handler function to handle
     * all incoming requests.
     * Params:
     *   handlerFunc = The function to use to handle requests.
     *   config = The server configuration.
     */
    this(
        HttpRequestHandlerFunction handlerFunc,
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
        trace("Initialized server socket.");
        if (this.config.reuseAddress) {
            this.serverSocket.setOption(SocketOptionLevel.SOCKET, SocketOption.REUSEADDR, 1);
            debug_("Enabled REUSEADDR socket option.");
        }
        trace("Calling preBindCallbacks.");
        foreach (socketConfigFunction; this.config.preBindCallbacks) {
            socketConfigFunction(this.serverSocket);
        }
        this.serverSocket.bind(this.address);
        infoF!"Bound to address %s"(this.address);
        this.serverSocket.listen(this.config.connectionQueueSize);
        debug_("Started listening for connections.");
        atomicStore(this.ready, true);
        this.workerPool.start();
        if (this.websocketManager !is null) {
            this.websocketManager.start();
        }

        info("Now accepting connections.");
        while (this.serverSocket.isAlive()) {
            try {
                Socket clientSocket = this.serverSocket.accept();
                synchronized(requestQueueMutex.writer) {
                    this.requestQueue.insertBack(clientSocket);
                }
                this.requestSemaphore.notify();
            } catch (SocketAcceptException acceptException) {
                if (this.serverSocket.isAlive()) {
                    warnF!"Socket accept failed: %s"(acceptException.msg);
                }
            }
        }
        atomicStore(this.ready, false);
        this.workerPool.stop();
        if (this.websocketManager !is null) {
            this.websocketManager.stop();
            this.websocketManager.join();
        }
        info("Server shut down.");
    }

    /**
     * Starts the server running in a new thread.
     * Returns: The thread that the server is running in.
     */
    public Thread startInNewThread() {
        Thread t = new Thread(&this.start);
        t.start();
        return t;
    }

    /** 
     * Shuts down the server by closing the server socket, if possible. This
     * will block until all pending requests have been fulfilled.
     */
    public void stop() {
        info("Stopping the server.");
        if (this.serverSocket !is null) {
            this.serverSocket.shutdown(SocketShutdown.BOTH);
            this.serverSocket.close();
        }
    }

    /** 
     * Tells whether the server is ready to receive requests. This loads the
     * ready status safely for access by multiple threads.
     * Returns: Whether the server is ready to receive requests.
     */
    public bool isReady() {
        return atomicLoad(this.ready);
    }

    /** 
     * Blocks the calling thread until we're notified by a semaphore, and tries
     * to obtain the next socket to a client for which we should process a
     * request.
     * 
     * This method is intended to be called by worker threads.
     *
     * Returns: A nullable socket, which, if not null, contains a socket that's
     * ready for request processing.
     */
    public Nullable!Socket waitForNextClient() {
        import std.datetime : seconds;
        Nullable!Socket result;
        try {
            bool notified = this.requestSemaphore.wait(seconds(10));
            if (notified) {
                synchronized(requestQueueMutex.writer) {
                    if (!this.requestQueue.empty) {
                        result = this.requestQueue.removeAny();
                    }
                }
            }
        } catch (SyncError e) {
            errorF!"SyncError occurred while waiting for the next client: %s"(e.msg);
        }
        return result;
    }

    /** 
     * Notifies all worker threads waiting on incoming requests. This is called
     * by the worker pool when it shuts down, to cause all workers to quit waiting.
     */
    public void notifyWorkerThreads() {
        for (int i = 0; i < this.config.workerPoolSize; i++) {
            this.requestSemaphore.notify();
            this.requestSemaphore.notify();
        }
    }

    /** 
     * Gets the configured handler for requests.
     * Returns: The handler.
     */
    public HttpRequestHandler getHandler() {
        return handler;
    }

    /** 
     * Gets the configured exception handler for any exceptions that occur
     * during request handling.
     * Returns: The exception handler.
     */
    public ServerExceptionHandler getExceptionHandler() {
        return exceptionHandler;
    }

    /**
     * Sets the server's exception handler.
     * Params:
     *   exceptionHandler = The exception handler to use.
     */
    public void setExceptionHandler(ServerExceptionHandler exceptionHandler) {
        this.exceptionHandler = exceptionHandler;
    }

    /**
     * Gets the server's websocket manager, used to register new websocket
     * connections, or to broadcast a message to all connected websockets.
     * Returns: The websocket manager, or `null` if `enableWebSockets` is set
     * to `false` in this server's configuration.
     */
    public WebSocketManager getWebSocketManager() {
        return this.websocketManager;
    }

    /**
     * Attempts to revive a dead websocket manager thread by simply replacing
     * it with a new one and starting that. This is only meant as a means to
     * minimize damage when there's a severe bug in websocket logic.
     */
    public void reviveWebSocketManager() {
        this.websocketManager = new WebSocketManager();
        this.websocketManager.start();
    }
}
