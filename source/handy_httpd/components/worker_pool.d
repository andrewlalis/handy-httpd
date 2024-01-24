module handy_httpd.components.worker_pool;

import std.socket : Socket;

/**
 * A pool to which connecting client sockets can be submitted so that their
 * requests may be handled.
 */
interface RequestWorkerPool {
    /**
     * Starts the pool, so that it will be able to process requests.
     */
    void start();

    /**
     * Submits a client socket to this pool for processing.
     * Params:
     *   socket = The client socket.
     */
    void submit(Socket socket);

    /**
     * Stops the pool, so that no more requests may be processed.
     */
    void stop();
}

/**
 * A basic worker pool implementation that uses Phobos' std.parallelism and
 * its TaskPool to asynchronously process requests. Due to the temporary nature
 * of Phobos' tasks, a new receive buffer must be allocated for each request.
 */
class TaskPoolWorkerPool : RequestWorkerPool {
    import std.parallelism;
    import handy_httpd.components.worker;
    import handy_httpd.server : HttpServer;
    import handy_httpd.components.parse_utils : Msg;
    import httparsed : initParser, MsgParser;
    
    private TaskPool taskPool;
    private HttpServer server;
    private size_t workerCount;

    this(HttpServer server, size_t workerCount) {
        this.server = server;
        this.workerCount = workerCount;
    }

    void start() {
        this.taskPool = new TaskPool(this.workerCount);
    }

    void submit(Socket socket) {
        ubyte[] receiveBuffer = new ubyte[server.config.receiveBufferSize];
        MsgParser!Msg requestParser = initParser!Msg();
        auto t = task!handleClient(
            server,
            socket,
            receiveBuffer,
            requestParser
        );
        this.taskPool.put(t);
    }

    void stop() {
        this.taskPool.finish(true);
    }
}
