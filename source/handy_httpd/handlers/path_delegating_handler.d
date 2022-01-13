module handy_httpd.handlers.path_delegating_handler;

import std.stdio;

import handy_httpd.handler;
import handy_httpd.request;
import handy_httpd.response;
import handy_httpd.responses;

/** 
 * A request handler that delegates handling of requests to other handlers,
 * based on a configured Ant-style path pattern.
 */
class PathDelegatingHandler : HttpRequestHandler {
    /** 
     * The associative array that maps path patterns to request handlers.
     */
    private HttpRequestHandler[string] handlers;

    this(HttpRequestHandler[string] handlers = null) {
        this.handlers = handlers;
    }

    /** 
     * Adds a new path/handler to this delegating handler.
     * Params:
     *   path = The path pattern to match against requests.
     *   handler = The handler that will handle requests to the given path.
     * Returns: This handler, for method chaining.
     */
    public PathDelegatingHandler addPath(string path, HttpRequestHandler handler) {
        this.handlers[path] = handler;
        return this;
    }

    HttpResponse handle(HttpRequest request) {
        foreach (pattern, handler; handlers) {
            if (pathMatches(pattern, request.url)) {
                if (request.server.isVerbose()) {
                    writefln!"Found matching handler for url %s (pattern: %s)"(request.url, pattern);
                }
                return handler.handle(request);
            }
        }
        if (request.server.isVerbose()) {
            writefln!"No matching handler found for url %s"(request.url);
        }
        return notFound();
    }
}

unittest {
    import handy_httpd.server;
    import handy_httpd.responses;
    import core.thread;

    auto handler = new PathDelegatingHandler()
        .addPath("/home", simpleHandler(request => okResponse()))
        .addPath("/users", simpleHandler(request => okResponse()))
        .addPath("/users/{id}", simpleHandler(request => okResponse()));

    HttpServer server = new HttpServer(handler).setVerbose(true);
    new Thread(() {server.start();}).start();
    while (!server.isReady()) Thread.sleep(msecs(10));

    import std.net.curl;
    import std.string;
    import std.exception;

    assert(get("http://localhost:8080/home") == "");
    assert(get("http://localhost:8080/home/") == "");
    assert(get("http://localhost:8080/users") == "");
    assert(get("http://localhost:8080/users/andrew") == "");
    assertThrown!CurlException(get("http://localhost:8080/not-home"));
    assertThrown!CurlException(get("http://localhost:8080/users/andrew/data"));

    server.stop();
}

/** 
 * Checks if a url matches an Ant-style path pattern. We do this by doing some
 * pre-processing on the pattern to convert it to a regular expression that can
 * be matched against the given url.
 * Params:
 *   pattern = The url pattern to check for a match with.
 *   url = The url to check against.
 * Returns: True if the given url matches the pattern, or false otherwise.
 */
private bool pathMatches(string pattern, string url) {
    import std.regex;
    auto multiSegmentRegex = ctRegex!(`\*\*`);
    auto singleSegmentRegex = ctRegex!(`(?<!\.)\*`);
    auto singleCharRegex = ctRegex!(`\?`);
    auto pathParamRegex = ctRegex!(`\{[^/]+\}`);

    string s = pattern.replaceAll(multiSegmentRegex, ".*")
        .replaceAll(singleSegmentRegex, "[^/]+")
        .replaceAll(singleCharRegex, "[^/]")
        .replaceAll(pathParamRegex, "[^/]+");
    Captures!string c = matchFirst(url, s);
    // import std.stdio;
    // writefln!"%s matched on %s using regex %s gives matches %s"(url, pattern, s, c);
    return !c.empty() && c.front() == url;
}

unittest {
    assert(pathMatches("/**", "/help"));
    assert(pathMatches("/**", "/"));
    assert(pathMatches("/*", "/help"));
    assert(pathMatches("/help", "/help"));
    assert(pathMatches("/help/*", "/help/other"));
    assert(pathMatches("/help/**", "/help/other"));
    assert(pathMatches("/help/**", "/help/other/another"));
    assert(pathMatches("/?elp", "/help"));
    assert(pathMatches("/**/test", "/hello/world/test"));
    assert(pathMatches("/users/{id}", "/users/1"));

    assert(!pathMatches("/help", "/Help"));
    assert(!pathMatches("/help", "/help/other"));
    assert(!pathMatches("/*", "/"));
    assert(!pathMatches("/help/*", "/help/other/other"));
    assert(!pathMatches("/users/{id}", "/users"));
    assert(!pathMatches("/users/{id}", "/users/1/2/3"));
}
