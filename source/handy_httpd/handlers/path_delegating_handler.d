module handy_httpd.handlers.path_delegating_handler;

import handy_httpd.components.handler;
import handy_httpd.components.request;
import handy_httpd.components.response;
import handy_httpd.components.responses;

/** 
 * A request handler that delegates handling of requests to other handlers,
 * based on a configured Ant-style path pattern.
 */
class PathDelegatingHandler : HttpRequestHandler {
    /** 
     * The associative array that maps path patterns to request handlers.
     */
    private HttpRequestHandler[string] handlers;

    /** 
     * A handler to delegate to when no matching handler is found for a
     * request. Defaults to a simple 404 response.
     */
    private HttpRequestHandler notFoundHandler;

    this(HttpRequestHandler[string] handlers = null) {
        this.handlers = handlers;
        this.notFoundHandler = toHandler((ref ctx) {ctx.response.notFound();});
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

    /** 
     * Adds a new function to handle requests to the given path.
     * Params:
     *   path = The path pattern to match against requests.
     *   fn = The function that will handle requests to the given path.
     * Returns: This handler, for method chaining.
     */
    public PathDelegatingHandler addPath(string path, HttpRequestHandlerFunction fn) {
        this.handlers[path] = toHandler(fn);
        return this;
    }

    /** 
     * Sets a handler to use when no matching handler was found for a request's
     * path.
     * Params:
     *   handler = The handler to use. It should not be null.
     * Returns: This handler, for method chaining.
     */
    public PathDelegatingHandler setNotFoundHandler(HttpRequestHandler handler) {
        if (handler is null) throw new Exception("Cannot set notFoundHandler to null.");
        this.notFoundHandler = handler;
        return this;
    }

    /** 
     * Handles an incoming request by delegating to the first registered
     * handler that matches the request's url path. If no handler is found,
     * a 404 NOT FOUND response is sent by default.
     * Params:
     *   ctx = The request context.
     */
    void handle(ref HttpRequestContext ctx) {
        auto log = ctx.server.getLogger();
        foreach (pattern, handler; handlers) {
            if (pathMatches(pattern, ctx.request.url)) {
                log.infoFV!"Found matching handler for url %s (pattern: %s)"(ctx.request.url, pattern);
                ctx.request.pathParams = parsePathParams(pattern, ctx.request.url);
                handler.handle(ctx);
                return; // Exit once we handle the request.
            }
        }
        log.infoFV!"No matching handler found for url %s"(ctx.request.url);
        notFoundHandler.handle(ctx);
    }
}

unittest {
    import handy_httpd.server;
    import handy_httpd.components.config;
    import handy_httpd.components.responses;
    import std.socket;
    import std.stdio;
    import unit_threaded;

    auto handler = new PathDelegatingHandler()
        .addPath("/home", (ref ctx) {ctx.response.okResponse();})
        .addPath("/users", (ref ctx) {ctx.response.okResponse();})
        .addPath("/users/{id}", (ref ctx) {ctx.response.okResponse();});

    /*
    To test the handle() method, we create a pair of dummy sockets and a dummy
    server to satisfy dependencies, then create some fake request contexts and
    see how the handler changes them.
    */
    Socket[2] sockets = socketPair();
    Socket clientSocket = sockets[1];
    HttpServer server = new HttpServer(handler);

    auto ctx1 = new HttpRequestContextBuilder(server, clientSocket)
        .withRequest("GET", "/home")
        .build();
    handler.handle(ctx1);
    assert(ctx1.response.status == 200);
    
    auto ctx2 = new HttpRequestContextBuilder(server, clientSocket)
        .withRequest("GET", "/home-not-exists")
        .build();
    handler.handle(ctx2);
    assert(ctx2.response.status == 404);

    auto ctx3 = new HttpRequestContextBuilder(server, clientSocket)
        .withRequest("GET", "/users/34")
        .build();
    handler.handle(ctx3);
    assert(ctx3.response.status == 200);
    assert(ctx3.request.pathParams["id"] == "34");
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

/** 
 * Parses a set of named path parameters from a url, according to a given path
 * pattern where named path parameters are indicated by curly braces.
 *
 * For example, the pattern string "/users/{id}" can be used to parse the url
 * "/users/123" to obtain ["id": "123"] as the path parameters.
 * Params:
 *   pattern = The path pattern to use to parse params from.
 *   url = The url to parse parameters from.
 * Returns: An associative array containing the path parameters.
 */
private string[string] parsePathParams(string pattern, string url) {
    import std.regex;
    import std.container.dlist;

    // First collect an ordered list of the names of all path parameters to look for.
    auto pathParamRegex = ctRegex!(`\{([^/]+)\}`);
    DList!string pathParams = DList!string();
    auto m = matchAll(pattern, pathParamRegex);
    while (!m.empty) {
        auto c = m.front();
        pathParams.insertFront(c[1]);
        m.popFront();
    }

    string[string] params;

    // Now parse all path parameters in order, and add them to the array.
    string preparedPathPattern = replaceAll(pattern, pathParamRegex, "([^/]+)");
    auto c = matchFirst(url, regex(preparedPathPattern));
    if (c.empty) return params; // If there's complete no matching, just exit.
    c.popFront(); // Pop the first capture group, which contains the full match.
    while (!c.empty) {
        if (pathParams.empty()) break;
        string expectedParamName = pathParams.back();
        pathParams.removeBack();
        params[expectedParamName] = c.front();
        c.popFront();
    }
    return params;
}

unittest {
    assert(parsePathParams("/users/{id}", "/users/1") == ["id": "1"]);
    assert(parsePathParams("/users/{id}/{name}", "/users/123/andrew") == ["id": "123", "name": "andrew"]);
    assert(parsePathParams("/users/{id}", "/users") == null);
    assert(parsePathParams("/users", "/users") == null);
    assert(parsePathParams("/{a}/b/{c}", "/one/b/two") == ["a": "one", "c": "two"]);
}
