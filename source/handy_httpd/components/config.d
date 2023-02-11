/** 
 * Module containing the server configuration and associated functions.
 */
module handy_httpd.components.config;

import handy_httpd.components.logger;
import std.socket : Socket;

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
     * The number of worker threads for processing requests.
     */
    size_t workerPoolSize;

    /** 
     * An alias for a delegate function that can be used to modify a socket.
     */
    alias SocketConfigureFunction = void delegate(Socket socket);

    /** 
     * A set of functions to run before the server's socket is bound.
     */
    SocketConfigureFunction[] preBindCallbacks;

    /** 
     * Whether to set the REUSEADDR flag for the socket.
     */
    bool reuseAddress;

    /** 
     * A set of default headers that are added to all HTTP responses.
     */
    string[string] defaultHeaders;

    /** 
     * The log level to use for server-specific logs.
     */
    LogLevel serverLogLevel;

    /** 
     * The default log level to use for logging within the context of request
     * handlers.
     */
    LogLevel defaultHandlerLogLevel;

    static ServerConfig defaultValues() {
        ServerConfig cfg;
        cfg.hostname = "127.0.0.1";
        cfg.port = 8080;
        cfg.receiveBufferSize = 8192;
        cfg.connectionQueueSize = 100;
        cfg.reuseAddress = true;
        cfg.workerPoolSize = 25;
        cfg.serverLogLevel = LogLevel.ERROR;
        cfg.defaultHandlerLogLevel = LogLevel.INFO;
        return cfg;
    }
}
