module handy_httpd.server;

import std.stdio;
import std.socket;
import std.regex;
import std.parallelism;

import handy_httpd.request;
import handy_httpd.response;
import handy_httpd.handler;
import handy_httpd.parse_utils;

/** 
 * A simple HTTP server that accepts requests on a given port and address, and
 * lets a configured HttpRequestHandler produce a response, to send back to the
 * client.
 */
class HttpServer {
    private Address address;
    size_t receiveBufferSize;
    int connectionQueueSize;
    private bool verbose;
    private HttpRequestHandler handler;
    private TaskPool workerPool;
    private bool ready = false;
    private Socket serverSocket = null;

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
        
        this.workerPool = new TaskPool(workerPoolSize);
        this.workerPool.isDaemon = true;
    }

    /** 
     * Starts the server on the calling thread, so that it will begin accepting
     * HTTP requests. Once the server is able to accept requests, `isReady()`
     * will return true, and will remain true until the server is stopped by
     * calling `stop()`.
     */
    public void start() {
        serverSocket = new TcpSocket();
        serverSocket.bind(this.address);
        if (this.verbose) writefln("Bound to address %s", this.address);
        serverSocket.listen(this.connectionQueueSize);
        if (this.verbose) writeln("Now accepting connections.");
        this.ready = true;
        while (serverSocket.isAlive()) {
            auto clientSocket = serverSocket.accept();
            workerPool.put(task!handleRequest(
                clientSocket,
                this.handler,
                this.receiveBufferSize,
                this.verbose
            ));
        }
        this.ready = false;
    }

    /** 
     * Shuts down the server by closing the server socket, if possible. Note
     * that this is not a blocking call, and the server will shutdown sometime
     * after this is called.
     */
    public void stop() {
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
}

/** 
 * Handles an HTTP request. It is intended for this function to be called as
 * an asynchronous task by the server's task pool.
 * Params:
 *   clientSocket = The socket to send responses to.
 *   handler = The handler that will handle the request.
 *   bufferSize = The buffer size to use when reading the request.
 *   verbose = Whether to print verbose log information.
 */
private void handleRequest(Socket clientSocket, HttpRequestHandler handler, size_t bufferSize, bool verbose) {
    ubyte[] receiveBuffer = new ubyte[bufferSize];
    auto received = clientSocket.receive(receiveBuffer);
    string data = cast(string) receiveBuffer[0..received];
    auto request = parseRequest(data);
    if (verbose) writefln!"<- %s %s"(request.method, request.url);
    try {
        auto response = handler.handle(request);
        clientSocket.send(response.toBytes());
        if (verbose) writefln!"\t-> %d %s"(response.status, response.statusText);
    } catch (Exception e) {
        writefln!"An error occurred while handling a request: %s"(e.msg);
    }
    clientSocket.close();
}
