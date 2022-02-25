/** 
 * Contains the core HTTP server components.
 */
module handy_httpd.server;

import std.stdio;
import std.socket;
import std.regex;
import std.container.dlist : DList;
import core.sync.semaphore : Semaphore;
import core.atomic : atomicLoad;
import core.thread.threadgroup : ThreadGroup;

import handy_httpd.request;
import handy_httpd.response;
import handy_httpd.handler;
import handy_httpd.parse_utils : parseRequest, Msg;

import httparsed : MsgParser, initParser;

/** 
 * A simple HTTP server that accepts requests on a given port and address, and
 * lets a configured HttpRequestHandler produce a response, to send back to the
 * client.
 */
class HttpServer {
    private Address address;
    private size_t receiveBufferSize;
    private int connectionQueueSize;
    private size_t workerPoolSize;
    private bool verbose;
    private HttpRequestHandler handler;
    private shared bool ready = false;
    private Socket serverSocket = null;
    private Semaphore requestSemaphore;
    private DList!Socket requestQueue;

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
        this.workerPoolSize = workerPoolSize;
        this.verbose = verbose;
        this.handler = handler;
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
        this.ready = true;

        // Initialize worker threads.
        this.requestSemaphore = new Semaphore();
        ThreadGroup tg = new ThreadGroup();
        for (int i = 0; i < this.workerPoolSize; i++) {
            tg.create(&workerThreadFunction);
        }

        if (this.verbose) writeln("Now accepting connections.");
        while (serverSocket.isAlive()) {
            Socket clientSocket = serverSocket.accept();
            this.requestQueue.insertBack(clientSocket);
            this.requestSemaphore.notify();
        }
        this.ready = false;
        
        // Shutdown worker threads. We call notify() one last time to stop them waiting.
        for (int i = 0; i < this.workerPoolSize; i++) {
            this.requestSemaphore.notify();
        }
        tg.joinAll();
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

    /** 
     * Worker function that runs for all worker threads that process incoming
     * requests. Workers will wait for the requestSemaphore to be notified so
     * that they can process a request. The worker will stay alive as long as
     * this server is set as ready.
     */
    private void workerThreadFunction() {
        MsgParser!Msg requestParser = initParser!Msg();
        ubyte[] receiveBuffer = new ubyte[this.receiveBufferSize];
        while (atomicLoad(this.ready)) {
            this.requestSemaphore.wait();
            if (!this.requestQueue.empty) {
                Socket clientSocket = this.requestQueue.removeAny();
                auto received = clientSocket.receive(receiveBuffer);
                if (received == 0 || received == Socket.ERROR) {
                    continue; // Skip if we didn't receive valid data.
                }
                string data = cast(string) receiveBuffer[0..received];
                requestParser.msg.reset();
                auto request = parseRequest(requestParser, data);
                request.server = this;
                request.clientSocket = clientSocket;
                if (verbose) writefln!"<- %s %s"(request.method, request.url);
                try {
                    auto response = this.handler.handle(request);
                    clientSocket.send(response.toBytes());
                    if (verbose) writefln!"\t-> %d %s"(response.status, response.statusText);
                } catch (Exception e) {
                    writefln!"An error occurred while handling a request: %s"(e.msg);
                }
                clientSocket.close();
            }
        }
    }
}
