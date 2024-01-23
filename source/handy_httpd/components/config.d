/** 
 * Module containing the server configuration and associated functions.
 */
module handy_httpd.components.config;

import std.socket : Socket;
import slf4d;
import handy_httpd.server : HttpServer;

/** 
 * Configuration properties for the HttpServer.
 */
struct ServerConfig {
    /** 
     * The hostname that the server will bind to.
     */
    string hostname;

    /** 
     * The port that the server will bind to.
     */
    ushort port;

    /** 
     * The size of the buffer for receiving requests.
     */
    size_t receiveBufferSize;

    /** 
     * The number of connections to accept into the queue.
     */
    int connectionQueueSize;

    /**
     * The size of the internal queue used for distributing requests to workers.
     */
    size_t requestQueueSize;

    /** 
     * The number of worker threads for processing requests.
     */
    size_t workerPoolSize;

    /**
     * The number of milliseconds that the worker pool manager should wait
     * between each health check it performs.
     */
    uint workerPoolManagerIntervalMs;

    /** 
     * An alias for a delegate function that can be used to modify a socket.
     */
    alias SocketConfigureFunction = void delegate(Socket socket);

    /** 
     * A set of functions to run before the server's socket is bound.
     */
    SocketConfigureFunction[] preBindCallbacks;

    /**
     * An alias for a delegate function that is called after the server has
     * stopped.
     */
    alias ServerShutdownFunction = void delegate(HttpServer server);

    /**
     * A set of functions to run after the server has been stopped.
     */
    ServerShutdownFunction[] postShutdownCallbacks;

    /** 
     * Whether to set the REUSEADDR flag for the socket.
     */
    bool reuseAddress;

    /** 
     * A set of default headers that are added to all HTTP responses.
     */
    string[string] defaultHeaders;

    /**
     * Whether to enable websocket functionality. If enabled, an extra thread
     * is spawned to manage websocket connections, separate from the main
     * worker pool.
     */
    bool enableWebSockets;

    static ServerConfig defaultValues() {
        ServerConfig cfg;
        cfg.hostname = "127.0.0.1";
        cfg.port = 8080;
        cfg.receiveBufferSize = 8192;
        cfg.requestQueueSize = 128;
        cfg.connectionQueueSize = 100;
        cfg.reuseAddress = true;
        cfg.workerPoolSize = 25;
        cfg.workerPoolManagerIntervalMs = 60_000;
        cfg.enableWebSockets = false;
        return cfg;
    }
}
