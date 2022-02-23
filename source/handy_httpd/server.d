/** 
 * Contains the core HTTP server components.
 */
module handy_httpd.server;

import std.stdio;
import std.socket;
import std.regex;

import handy_httpd.request;
import handy_httpd.response;
import handy_httpd.handler;
import handy_httpd.worker;

/** 
 * A simple HTTP server that accepts requests on a given port and address, and
 * lets a configured HttpRequestHandler produce a response, to send back to the
 * client.
 */
class HttpServer {
    private Address address;
    private size_t receiveBufferSize;
    private int connectionQueueSize;
    private bool verbose;
    private HttpRequestHandler handler;
    private bool ready = false;
    private Socket serverSocket = null;
    private HttpServerWorker[] workers;

    this(
        HttpRequestHandler handler = noOpHandler(),
        string hostname = "127.0.0.1",
        ushort port = 8080,
        size_t receiveBufferSize = 8192,
        int connectionQueueSize = 100,
        bool verbose = false,
        size_t workerPoolSize = 25
    ) {
        this.address = parseAddress(hostname, port);
        this.receiveBufferSize = receiveBufferSize;
        this.connectionQueueSize = connectionQueueSize;
        this.verbose = verbose;
        this.handler = handler;

        this.workers.length = workerPoolSize;
        for (size_t i = 0; i < workerPoolSize; i++) {
            this.workers[i] = new HttpServerWorker(receiveBufferSize);
            this.workers[i].start(); // Start all workers so their threads are spawned and ready for requests.
        }
    }

    /**
     * Will be called before the socket is bound to the address. One can set
     * special socket options in here by overriding it. 
     * 
     * Note: one application would be to add SocketOption.REUSEADDR, in 
     * order to prevent long TIME_WAIT states preventing quick restarts 
     * of the server after termination on some systems. Learn more about it
     * here: https://stackoverflow.com/a/14388707.
     */
    protected void configurePreBind(Socket socket) {}

    /** 
     * Starts the server on the calling thread, so that it will begin accepting
     * HTTP requests. Once the server is able to accept requests, `isReady()`
     * will return true, and will remain true until the server is stopped by
     * calling `stop()`.
     */
    public void start() {
        serverSocket = new TcpSocket();
        configurePreBind(serverSocket);
        serverSocket.bind(this.address);
        if (this.verbose) writefln!"Bound to address %s"(this.address);
        serverSocket.listen(this.connectionQueueSize);
        if (this.verbose) writeln("Now accepting connections.");
        this.ready = true;
        while (serverSocket.isAlive()) {
            Socket clientSocket = serverSocket.accept();
            HttpServerWorker worker = getBestWorker();
            worker.queueRequest(clientSocket, this, this.handler);
            worker.start();
        }
        this.ready = false;
    }

    /** 
     * Searches for the best worker in our pool to handle the next request.
     * Generally, this is the first available worker that's not running and has
     * nothing in its queue, but if we're busy, we choose the worker whose
     * queue is the smallest.
     * Returns: The best worker to handle the next request.
     */
    private HttpServerWorker getBestWorker() {
        ubyte minQueueSize = 255;
        HttpServerWorker bestWorker = null;
        foreach (i, worker; this.workers) {
            // Quickly find best worker.
            if (!worker.isRunning() && worker.getQueueSize() == 0) return worker;
            if (worker.getQueueSize() < minQueueSize) {
                minQueueSize = worker.getQueueSize();
                bestWorker = worker;
            }
        }
        if (bestWorker is null) throw new Exception("No available worker!");
        return bestWorker;
    }

    /** 
     * Shuts down the server by closing the server socket, if possible. This
     * will block until all pending requests have been fulfilled.
     */
    public void stop() {
        if (verbose) writeln("Stopping the server.");
        if (serverSocket !is null) {
            serverSocket.close();
        }
        foreach (i, worker; this.workers) {
            worker.join(false);
        }
    }

    /** 
     * Tells whether the server is ready to receive requests.
     * Returns: Whether the server is ready to receive requests.
     */
    public bool isReady() {
        return ready;
    }

    /** 
     * Sets the server's verbosity, which determines whether detailed log
     * messages are printed during runtime.
     * Params:
     *   verbose = Whether to enable verbose output.
     * Returns: The server instance, for method chaining.
     */
    public HttpServer setVerbose(bool verbose) {
        this.verbose = verbose;
        return this;
    }

    /** 
     * Tells whether the server will give verbose output.
     * Returns: Whether the server is set to give verbose output.
     */
    public bool isVerbose() {
        return this.verbose;
    }
}
