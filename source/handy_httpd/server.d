/** 
 * Contains the core HTTP server implementation.
 */
module handy_httpd.server;

import std.socket;
import std.conv : to, ConvException;
import std.typecons : Nullable;
import core.sync.exception;
import core.atomic : atomicStore, atomicLoad;
import core.thread : Thread;
import core.thread.threadgroup : ThreadGroup;

import handy_httpd.components.handler;
import handy_httpd.components.config;
import handy_httpd.components.worker;
import handy_httpd.components.request_queue;
import handy_httpd.components.worker_pool;
import handy_httpd.components.legacy_worker_pool;
import handy_httpd.components.distributing_worker_pool;
import handy_httpd.components.websocket;

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

    /**
     * The worker pool to which accepted client sockets are submitted for
     * processing.
     */
    private RequestWorkerPool requestWorkerPool;

    /**
     * A manager thread for handling all websocket connections.
     */
    private WebSocketManager websocketManager;

    /**
     * Constructs a new server using the supplied handler to handle all
     * incoming requests, as well as a supplied request worker pool.
     * Params:
     *   handler = The handler to use.
     *   requestWorkerPool = The worker pool to use.
     *   config = The server configuration.
     */
    this(
        HttpRequestHandler handler,
        RequestWorkerPool requestWorkerPool,
        ServerConfig config
    ) {
        this.config = config;
        this.address = parseAddress(config.hostname, config.port);
        this.handler = handler;
        this.exceptionHandler = new BasicServerExceptionHandler();
        this.requestWorkerPool = requestWorkerPool;
        if (config.enableWebSockets) {
            this.websocketManager = new WebSocketManager();
        }
    }

    /**
     * Constructs a new server using the supplied handler to handle all
     * incoming requests.
     * Params:
     *   handler = The handler to handle all requests.
     *   config = The server configuration.
     */
    this(
        HttpRequestHandler handler = noOpHandler(),
        ServerConfig config = ServerConfig.init
    ) {
        this.config = config;
        this.address = parseAddress(config.hostname, config.port);
        this.handler = handler;
        this.exceptionHandler = new BasicServerExceptionHandler();
        this.requestWorkerPool = new DistributingWorkerPool(config.receiveBufferSize, config.workerPoolSize);
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
    this(F)(
        F handlerFunc,
        ServerConfig config = ServerConfig.init
    ) if (isHttpRequestHandlerFunction!F) {
        this(toHandler(handlerFunc), config);
    }

    /** 
     * Starts the server on the calling thread, so that it will begin accepting
     * HTTP requests. Once the server is able to accept requests, `isReady()`
     * will return true, and will remain true until the server is stopped by
     * calling `stop()`. This can be thought of as the "main loop" of the
     * server.
     */
    public void start() {
        this.prepareToStart();
        atomicStore(this.ready, true);
        trace("Set ready flag to true.");
        this.requestWorkerPool.start();
        info("Now accepting connections.");
        while (this.serverSocket.isAlive()) {
            try {
                Socket clientSocket = this.serverSocket.accept();
                this.requestWorkerPool.submit(this, clientSocket);
            } catch (SocketAcceptException acceptException) {
                if (this.serverSocket.isAlive()) {
                    warnF!"Socket accept failed: %s"(acceptException.msg);
                }
            }
        }
        atomicStore(this.ready, false);
        trace("Set ready flag to false.");
        this.cleanUpAfterStop();
        info("Server shut down.");
    }

    /**
     * Internal method that's called before starting the server, which prepares
     * all of the resources necessary to start.
     */
    private void prepareToStart() {
        this.serverSocket = new TcpSocket();
        trace("Initialized server socket.");
        if (this.config.reuseAddress) {
            this.serverSocket.setOption(SocketOptionLevel.SOCKET, SocketOption.REUSEADDR, 1);
            debug_("Enabled REUSEADDR socket option.");
        }
        trace("Calling pre-bind callbacks.");
        foreach (socketConfigFunction; this.config.preBindCallbacks) {
            socketConfigFunction(this.serverSocket);
        }
        this.serverSocket.bind(this.address);
        infoF!"Bound to address %s"(this.address);
        this.serverSocket.listen(this.config.connectionQueueSize);
        debug_("Started listening for connections.");
        if (this.websocketManager !is null) {
            this.websocketManager.start();
        }
    }

    /**
     * Internal method that's called after the server has been stopped, to
     * clean up any additonal resources or threads spawned by the server.
     */
    private void cleanUpAfterStop() {
        this.requestWorkerPool.stop();
        if (this.websocketManager !is null) {
            this.websocketManager.stop();
            try {
                this.websocketManager.join();
            } catch (Exception e) {
                error("Failed to join websocketManager thread because an exception was thrown.", e);
            }
        }
        trace("Calling post-shutdown callbacks.");
        foreach (postShutdownCallback; this.config.postShutdownCallbacks) {
            postShutdownCallback(this);
        }
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
