module handy_httpd.server_config;
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
     * Whether to show verbose output.
     */
    bool verbose;

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
     * A set of default headers that are added to all HTTP responses.
     */
    string[string] defaultHeaders;

    static ServerConfig defaultValues() {
        ServerConfig cfg;
        cfg.hostname = "127.0.0.1";
        cfg.port = 8080;
        cfg.receiveBufferSize = 8192;
        cfg.connectionQueueSize = 100;
        cfg.verbose = false;
        cfg.workerPoolSize = 25;
        return cfg;
    }
}
