module handy_httpd.components.worker_pool2;

import std.socket : Socket;

interface RequestWorkerPool {
    void start();
    void submit(Socket socket);
    void stop();
}

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
