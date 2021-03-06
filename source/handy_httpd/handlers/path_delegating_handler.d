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

    void handle(ref HttpRequest request, ref HttpResponse response) {
        foreach (pattern, handler; handlers) {
            if (pathMatches(pattern, request.url)) {
                if (request.server.verbose) {
                    writefln!"Found matching handler for url %s (pattern: %s)"(request.url, pattern);
                }
                request.pathParams = parsePathParams(pattern, request.url);
                handler.handle(request, response);
                return; // Exit once we handle the request.
            }
        }
        if (request.server.verbose) {
            writefln!"No matching handler found for url %s"(request.url);
        }
        response.notFound();
    }
}

unittest {
    import handy_httpd.server;
    import handy_httpd.server_config;
    import handy_httpd.responses;
    import core.thread;

    auto handler = new PathDelegatingHandler()
        .addPath("/home", simpleHandler((ref request, ref response) {response.okResponse();}))
        .addPath("/users", simpleHandler((ref request, ref response) {response.okResponse();}))
        .addPath("/users/{id}", simpleHandler((ref request, ref response) {response.okResponse();}));

    ServerConfig config = ServerConfig.defaultValues();
    config.verbose = true;
    HttpServer server = new HttpServer(handler, config);
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
