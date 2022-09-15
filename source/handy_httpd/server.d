/** 
 * Contains the core HTTP server components.
 */
module handy_httpd.server;

import std.stdio;
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

import httparsed : MsgParser, initParser;

/** 
 * A simple HTTP server that accepts requests on a given port and address, and
 * lets a configured HttpRequestHandler produce a response, to send back to the
 * client.
 */
class HttpServer {
    public ServerConfig config;
    private Address address;
    private HttpRequestHandler handler;
    private shared bool ready = false;
    private Socket serverSocket = null;
    private Semaphore requestSemaphore;
    private DList!Socket requestQueue;
    private ThreadGroup workerThreadGroup;

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
    }

    /** 
     * Constructs a new server using the supplied handler function to handle
     * all incoming requests.
     * Params:
     *   handlerFunc = The function to use to handle requests.
     *   config = The server configuration.
     */
    this(
        void function(ref HttpRequest request, ref HttpResponse response) handlerFunc,
        ServerConfig config = ServerConfig.defaultValues
    ) {
        this(simpleHandler(handlerFunc), config);
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
        if (this.config.verbose) writefln!"Bound to address %s"(this.address);
        this.serverSocket.listen(this.config.connectionQueueSize);
        initWorkerThreads();
        this.ready = true;

        if (this.config.verbose) writeln("Now accepting connections.");
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
        if (this.config.verbose) writeln("Stopping the server.");
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
                auto received = clientSocket.receive(receiveBuffer);
                if (received == 0 || received == Socket.ERROR) {
                    continue; // Skip if we didn't receive valid data.
                }
                string data = receiveBuffer[0..received].idup;
                requestParser.msg.reset();
                auto request = parseRequest(requestParser, data);
                
                const(string*) pcontentLength = "Content-Length" in request.headers;
                if(pcontentLength !is null) {
                    try {
                        size_t contentLength = (*pcontentLength).to!size_t;
                        size_t recivedTotal = request.bodyContent.length;
                        while(recivedTotal < contentLength && received > 0) {
                            received = clientSocket.receive(receiveBuffer);
                            recivedTotal += received;
                            request.bodyContent ~= receiveBuffer[0..received].idup;
                        }
                    } catch(ConvException e) {
                        if (verbose) writefln!"Content-Length is not a number: %s"(e.msg);
                    }
                }

                request.server = this;
                request.clientSocket = clientSocket;
                if (verbose) writefln!"<- %s %s"(request.method, request.url);
                try {
                    HttpResponse response;
                    response.status = 200;
                    response.statusText = "OK";
                    response.clientSocket = clientSocket;
                    foreach (headerName, headerValue; this.config.defaultHeaders) {
                        response.addHeader(headerName, headerValue);
                    }
                    this.handler.handle(request, response);
                } catch (Exception e) {
                    writefln!"An error occurred while handling a request: %s"(e.msg);
                }
                clientSocket.close();
            }
        }
    }

    /** 
     * Shortcut for checking if a server is configured for verbose output.
     * Returns: Whether the server is configured for verbose output.
     */
    public bool verbose() {
        return this.config.verbose;
    }
}
