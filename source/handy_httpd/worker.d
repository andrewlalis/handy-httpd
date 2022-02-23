/** 
 * Contains components for the server's workers, which handle requests.
 */
module handy_httpd.worker;

import std.socket : Socket;
import std.container.dlist;
import std.stdio;
import core.thread;
import core.atomic : atomicOp;
import core.sync.mutex;

import handy_httpd.parse_utils : parseRequest, Msg;
import handy_httpd.server : HttpServer;
import handy_httpd.handler : HttpRequestHandler;

import httparsed : MsgParser, initParser;

/** 
 * Utility struct for keeping track of information for handling requests.
 */
private struct IncomingRequest {
    Socket clientSocket;
    HttpServer server;
    HttpRequestHandler handler;
}

/** 
 * An independent worker that handles incoming HTTP requests received by a
 * server.
 */
class HttpServerWorker : Thread {
    private DList!IncomingRequest requestQueue;
    private ubyte queueSize = 0;
    private ubyte[] receiveBuffer;
    private MsgParser!Msg requestParser;
    private Mutex queueMutex;

    public this(size_t receiveBufferSize) {
        super(&run);
        this.receiveBuffer = new ubyte[receiveBufferSize];
        this.requestParser = initParser!Msg();
        this.queueMutex = new Mutex();
    }

    /** 
     * Runs the worker to process any requests in its queue.
     */
    private void run() {
        this.queueMutex.lock_nothrow();
        while (!requestQueue.empty) {
            IncomingRequest ir = requestQueue.removeAny();
            this.queueSize--;
            handleRequest(ir.clientSocket, ir.server, ir.handler);
        }
        this.queueMutex.unlock_nothrow();
    }

    /** 
     * Adds a request to this worker's queue to be processed.
     * Params:
     *   clientSocket = The socket to use to communicate with the client.
     *   server = The server that received this request.
     *   handler = The handler that should handle the request.
     */
    public void queueRequest(Socket clientSocket, HttpServer server, HttpRequestHandler handler) {
        this.queueMutex.lock_nothrow();
        requestQueue.insertFront(IncomingRequest(clientSocket, server, handler));
        this.queueSize++;
        this.queueMutex.unlock_nothrow();
    }

    /** 
    * Handles an HTTP request.
    * Params:
    *   server = The HttpServer that's handling the request.
    *   clientSocket = The socket to send responses to.
    *   handler = The handler that will handle the request.
    */
    public void handleRequest(Socket clientSocket, HttpServer server, HttpRequestHandler handler) {
        auto received = clientSocket.receive(this.receiveBuffer);
        string data = cast(string) receiveBuffer[0..received];
        this.requestParser.msg.reset();
        auto request = parseRequest(this.requestParser, data);
        request.server = server;
        bool verbose = server.isVerbose();
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

    /** 
     * Gets this worker's queue size.
     * Returns: This worker's current queue size.
     */
    public ubyte getQueueSize() {
        return this.queueSize;
    }
}