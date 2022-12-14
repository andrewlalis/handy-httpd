/**
 * The main module of the handy-httpd server library. Importing this module
 * will publically import the basic components needed for most applications.
 */
module handy_httpd;

public import handy_httpd.server;
public import handy_httpd.components.config;
public import handy_httpd.components.request;
public import handy_httpd.components.response;
public import handy_httpd.components.handler;
public import handy_httpd.components.responses;

/** 
 * General-purpose testing for the HTTP server and its behavior.
 */
unittest {
    import std.stdio;
    import core.thread;
    import core.time;
    const ushort PORT = 45_312;

    /** 
     * Helper function to prepare an HTTP server for testing.
     * Returns: A simple HTTP server for testing.
     */
    HttpServer getSimpleServer() {
        ServerConfig config = ServerConfig.defaultValues();
        config.port = PORT;
        config.verbose = true;
        config.workerPoolSize = 10;
        auto s = new HttpServer(
            toHandler((ref ctx) {
                if (ctx.request.method == "GET") {
                    ctx.response.writeBody("Hello world!");
                } else {
                    ctx.response.methodNotAllowed();
                }
            }),
            config
        );
        // Start up the server in its own thread.
        new Thread(() {s.start();}).start();
        return s;
    }

    // Test that the server can start up and shut down properly.
    auto s = getSimpleServer();
    while (!s.isReady) {
        writeln("Waiting for server to be ready...");
        Thread.sleep(msecs(10));
    }
    assert(s.isReady);

    // Test basic HTTP request behavior.
    import std.net.curl;
    import std.string;
    import std.exception;
    string url = std.string.format!"http://localhost:%d"(PORT);
    
    assert(get(url) == "Hello world!");
    assertThrown!CurlException(post(url, ["hello"]));

    s.stop();
}
