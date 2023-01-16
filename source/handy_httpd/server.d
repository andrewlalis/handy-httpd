/** 
 * Contains the core HTTP server components.
 */
module handy_httpd.server;

import std.socket;
import std.conv : to, ConvException;
import std.container.dlist : DList;
import std.typecons : Nullable;
import core.sync.semaphore : Semaphore;
import core.atomic : atomicLoad;
import core.thread.threadgroup : ThreadGroup;

import handy_httpd.components.request;
import handy_httpd.components.response;
import handy_httpd.components.handler;
import handy_httpd.components.config;
import handy_httpd.components.parse_utils : parseRequest, Msg;
import handy_httpd.components.logger;
import handy_httpd.components.worker;

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
            try {
                Socket clientSocket = this.serverSocket.accept();
                this.requestQueue.insertBack(clientSocket);
                this.requestSemaphore.notify();
            } catch (SocketAcceptException acceptException) {
                log.infoFV!"Socket accept failed: %s"(acceptException.msg);
            }
        }
        this.ready = false;
        shutdownWorkerThreads();
    }

    unittest {
        
    }

    /** 
     * Shuts down the server by closing the server socket, if possible. This
     * will block until all pending requests have been fulfilled.
     */
    public void stop() {
        log.infoV("Stopping the server.");
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
        this.requestSemaphore.wait();
        Nullable!Socket result;
        if (!this.requestQueue.empty) {
            result = this.requestQueue.removeAny();
        }
        return result;
    }

    /** 
     * Spawns all worker threads in a new thread group, and initializes the
     * semaphore that they will use to be notified of work to do.
     */
    private void initWorkerThreads() {
        this.requestSemaphore = new Semaphore();
        this.workerThreadGroup = new ThreadGroup();
        for (int i = 1; i <= this.config.workerPoolSize; i++) {
            ServerWorkerThread worker = new ServerWorkerThread(this, i);
            worker.start();
            this.workerThreadGroup.add(worker);
        }
    }

    /** 
     * Shuts down all worker threads by sending one final semaphore notification
     * to all of them.
     */
    private void shutdownWorkerThreads() {
        for (int i = 0; i < this.config.workerPoolSize; i++) {
            this.requestSemaphore.notify();
            this.requestSemaphore.notify();
        }
        this.workerThreadGroup.joinAll();
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
     * Gets the server's logger.
     * Returns: The server's logger.
     */
    public ServerLogger getLogger() {
        return log;
    }
}
