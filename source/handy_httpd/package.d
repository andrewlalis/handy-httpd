module handy_httpd;

public import handy_httpd.server;
public import handy_httpd.request;
public import handy_httpd.response;
public import handy_httpd.handler;
public import handy_httpd.responses;

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
        auto s = new HttpServer(
            simpleHandler((request) {
                if (request.method == "GET") {
                    return okResponse().setBody("Hello world!");
                } else {
                    return methodNotAllowed();
                }
            }),
            "127.0.0.1",
            PORT,
            8192,
            100,
            true,
            10
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
