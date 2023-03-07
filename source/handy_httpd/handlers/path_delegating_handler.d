/** 
 * This module defines a handler that delegates to other handlers, depending on
 * the request URL path and/or request method. Matching is done based on a
 * provided "path pattern". The following are examples of valid path patterns:
 * - "/hello-world"  -> matches just the URL "/hello-world".
 * - "/settings/*"   -> matches any single URL segment under "/settings", like "/settings/privacy".
 * - "/users/**"     -> matches any zero or more segments under "/users", like "/users/42/data/name".
 * - "/events/{id}"  -> matches any URL starting with "/events", followed by a single "id" segment.
 * - "/data?/info"   -> matches any URL where "?" can be any single character, like "/datax/info".
 *
 * When a mapping is added to the PathDelegatingHandler via one of its
 * `addMapping` methods, the given path pattern is compiled to a regular
 * expression that's used to match request URLs at runtime.
 *
 * At runtime, if a PathDelegatingHandler receives a request for which no
 * mapping matches, then a configurable `notFoundHandler` is called to handle
 * request. By default, it just applies `handy_httpd.components.responses.notFound`
 * to it, setting the status code to 404 and adding a "Not Found" status text.
 */
module handy_httpd.handlers.path_delegating_handler;

import handy_httpd.components.handler;
import handy_httpd.components.request;
import handy_httpd.components.response;
import handy_httpd.components.responses;
import slf4d;

import std.regex;

/** 
 * A request handler that delegates handling of requests to other handlers,
 * based on a configured Ant-style path pattern.
 */
class PathDelegatingHandler : HttpRequestHandler {
    private HandlerMapping[] handlerMappings;

    /** 
     * A handler to delegate to when no matching handler is found for a
     * request. Defaults to a simple 404 response.
     */
    private HttpRequestHandler notFoundHandler;

    private string[string] pathVariableTypePatterns;

    this() {
        this.handlerMappings = [];
        this.notFoundHandler = toHandler((ref ctx) {ctx.response.notFound();});
        this.pathVariableTypePatterns = [
            "int": `-?[0-9]+`,
            "string": `\w+`
        ];
    }

    /** 
     * Adds a new path mapping to this handler, so that when handling requests,
     * if the request's URL matches the given path pattern, and the request's
     * method is one of the given methods, then the given handler will be used
     * to handle the request.
     *
     * For example, to invoke `myHandler` on GET and PATCH requests to `/users/{name}`,
     * we can add a mapping like so:
     * ```d
     * new PathDelegatingHandler()
     *     .addMapping(["GET", "PATCH"], "/users/{name}", myHandler);
     * ```
     *
     * To let a handler apply to any request method, you can also simply supply
     * `["*"]` as the `methods` argument.
     * ```d
     * new PathDelegatingHandler()
     *     .addMapping(["*"], "/users/{name}", myHandler);
     * ```
     *
     * Params:
     *   methods = The methods that the handler accepts.
     *   pathPattern = The path pattern the handler accepts.
     *   handler = The handler to handle requests.
     * Returns: This path delegating handler.
     */
    public PathDelegatingHandler addMapping(string[] methods, string pathPattern, HttpRequestHandler handler) {
        import std.algorithm;
        import std.string;
        import std.array;

        if (handler is null) throw new Exception("Cannot add a mapping for a null handler.");
        methods = methods
            .map!(m => toUpper(m)).array
            .sort!((a, b) => a < b).array;
        foreach (mapping; this.handlerMappings) {
            // TODO: Actually parse and check if path patterns overlap.
            if (mapping.pathPattern == pathPattern && mapping.methods == methods) {
                throw new Exception(
                    format!"A mapping already exists for methods %s and path %s."(methods, pathPattern)
                );
            }
        }
        sort(methods);
        this.handlerMappings ~= HandlerMapping(pathPattern, methods, handler);
        return this;
    }

    /** 
     * Overloaded version of `addMapping` that accepts a handler function.
     * Params:
     *   methods = The methods that the handler accepts.
     *   pathPattern = The path pattern the handler accepts.
     *   handler = The handler to handle requests.
     * Returns: This path delegating handler.
     */
    public PathDelegatingHandler addMapping(string[] methods, string pathPattern, HttpRequestHandlerFunction handler) {
        return this.addMapping(methods, pathPattern, toHandler(handler));
    }

    /** 
     * Overloaded version of `addMapping` that accepts a single method.
     * Params:
     *   method = The methods that the handler accepts.
     *   pathPattern = The path pattern the handler accepts.
     *   handler = The handler to handle requests.
     * Returns: This path delegating handler.
     */
    public PathDelegatingHandler addMapping(string method, string pathPattern, HttpRequestHandler handler) {
        return this.addMapping([method], pathPattern, handler);
    }

    /** 
     * Overloaded version of `addMapping` that accepts a single method and a
     * handler function.
     * Params:
     *   method = The methods that the handler accepts.
     *   pathPattern = The path pattern the handler accepts.
     *   handler = The handler to handle requests.
     * Returns: This path delegating handler.
     */
    public PathDelegatingHandler addMapping(string method, string pathPattern, HttpRequestHandlerFunction handler) {
        return this.addMapping([method], pathPattern, handler);
    }

    /** 
     * Overloaded version of `addMapping` that defaults to mapping all request
     * methods to the given handler.
     * Params:
     *   pathPattern = The path pattern the handler accepts.
     *   handler = The handler to handle requests.
     * Returns: This path delegating handler.
     */
    public PathDelegatingHandler addMapping(string pathPattern, HttpRequestHandler handler) {
        return this.addMapping(["*"], pathPattern, handler);
    }

    /** 
     * Overloaded version of `addMapping` that defaults to mapping all request
     * methods to the given handler function.
     * Params:
     *   pathPattern = The path pattern the handler accepts.
     *   handler = The handler to handle requests.
     * Returns: This path delegating handler.
     */
    public PathDelegatingHandler addMapping(string pathPattern, HttpRequestHandlerFunction handler) {
        return this.addMapping(["*"], pathPattern, handler);
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

    unittest {
        import std.exception;
        auto handler = new PathDelegatingHandler();
        assertThrown!Exception(handler.setNotFoundHandler(null));
        auto notFoundHandler = toHandler((ref ctx) {
            ctx.response.status = 404;
        });
        assertNotThrown!Exception(handler.setNotFoundHandler(notFoundHandler));
    }

    /** 
     * Handles an incoming request by delegating to the first registered
     * handler that matches the request's url path. If no handler is found,
     * a 404 NOT FOUND response is sent by default.
     * Params:
     *   ctx = The request context.
     */
    void handle(ref HttpRequestContext ctx) {
        import std.algorithm : canFind;
        auto log = getLogger();
        foreach (mapping; handlerMappings) {
            if (
                pathMatches(mapping.pathPattern, ctx.request.url) &&
                (
                    mapping.methods.length == 0 ||
                    mapping.methods[0] == "*" ||
                    canFind(mapping.methods, ctx.request.method)
                )
            ) {
                log.debugF!"Found matching handler for %s %s (pattern: %s)"(
                    ctx.request.method,
                    ctx.request.url,
                    mapping.pathPattern
                );
                ctx.request.pathParams = parsePathParams(mapping.pathPattern, ctx.request.url);
                mapping.handler.handle(ctx);
                return; // Exit once we handle the request.
            }
        }
        log.debugF!"No matching handler found for url %s"(ctx.request.url);
        notFoundHandler.handle(ctx);
    }

    unittest {
        import handy_httpd.server;
        import handy_httpd.components.responses;
        import handy_httpd.util.builders;
        import handy_httpd.util.range;

        auto handler = new PathDelegatingHandler()
            .addMapping("GET", "/home", (ref ctx) {ctx.response.okResponse();})
            .addMapping("GET", "/users", (ref ctx) {ctx.response.okResponse();})
            .addMapping("GET", "/users/{id}", (ref ctx) {ctx.response.okResponse();})
            .addMapping("GET", "/api/*", (ref ctx) {ctx.response.okResponse();});

        /*
        To test the handle() method, we create a pair of dummy sockets and a dummy
        server to satisfy dependencies, then create some fake request contexts and
        see how the handler changes them.
        */
        HttpRequestContext generateHandledCtx(string method, string url) {
            auto builder = new HttpRequestContextBuilder();
            builder.withServer(new HttpServer());
            builder.request()
                .withMethod(method)
                .withUrl(url);
            auto ctx = builder.build();
            handler.handle(ctx);
            return ctx;
        }

        assert(generateHandledCtx("GET", "/home").response.status == 200);
        assert(generateHandledCtx("GET", "/home-not-exists").response.status == 404);
        assert(generateHandledCtx("GET", "/users").response.status == 200);
        assert(generateHandledCtx("GET", "/users/34").response.status == 200);
        assert(generateHandledCtx("GET", "/users/34").request.getPathParamAs!int("id") == 34);
        assert(generateHandledCtx("GET", "/api/test").response.status == 200);
        assert(generateHandledCtx("GET", "/api/test/bleh").response.status == 404);
        assert(generateHandledCtx("GET", "/api").response.status == 404);
        assert(generateHandledCtx("GET", "/").response.status == 404);
    }
}

/** 
 * Represents a mapping of a specific request handler to a subset of URLs
 * and/or request methods.
 */
struct HandlerMapping {
    /** 
     * The pattern used to match against URLs.
     */
    string pathPattern;

    /** 
     * The set of methods that this handler mapping can be used for.
     */
    string[] methods;

    /** 
     * The handler to apply to requests whose URL and method match this
     * mapping's path pattern and methods list.
     */
    HttpRequestHandler handler;
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
    assert(pathMatches("/users/**", "/users/1"));

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
    // Check that if two path params have the same name, the last value is used.
    assert(parsePathParams("/{first}/{second}/{first}", "/a/b/c") == ["first": "c", "second": "b"]);
}

/** 
 * Compiles a "path pattern" into a Regex that can be used at runtime for
 * matching against request URLs. For the path pattern specification, please
 * see this module's documentation.
 * Params:
 *   pattern = The path pattern to compile.
 * Returns: A regex that matches URLs that match the given path pattern.
 */
public Regex!char compilePathPattern(string pattern) {
    import std.algorithm : canFind;
    import std.format : format;
    import std.array : replaceFirst;

    auto multiSegmentWildcardRegex = ctRegex!(`\*\*`);
    auto singleSegmentWildcardRegex = ctRegex!(`\*`);
    auto singleCharWildcardRegex = ctRegex!(`\?`);
    auto pathParamRegex = ctRegex!(`\{(?P<name>[a-zA-Z][a-zA-Z0-9_-]*)(?::(?P<type>[^}]+))?\}`);

    string originalPattern = pattern;

    // First pass, where we tag all wildcards for replacement on a second pass.
    pattern = replaceAll(pattern, multiSegmentWildcardRegex, "--<<MULTI_SEGMENT>>--");
    pattern = replaceAll(pattern, singleSegmentWildcardRegex, "--<<SINGLE_SEGMENT>>--");
    pattern = replaceAll(pattern, singleCharWildcardRegex, "--<<SINGLE_CHAR>>--");

    // Replace each path parameter expression with a named capture group for it.
    auto pathParamMatches = matchAll(pattern, pathParamRegex);
    string[] pathParamNames;
    foreach (capture; pathParamMatches) {
        string paramName = capture["name"];
        if (canFind(pathParamNames, paramName)) {
            throw new Exception(
                format!"Duplicate path parameter with name \"%s\" in pattern \"%s\"."(paramName, originalPattern)
            );
        }
        pathParamNames ~= paramName;

        string paramType = capture["type"];
        string paramPattern = "[^/]+";
        if (paramType !is null) {
            if (paramType == "int") {
                paramPattern = "-?[0-9]+";
            } else if (paramType == "string") {
                paramPattern = `\w+`;
            } else {
                paramPattern = paramType;
            }
        }
        pattern = replaceFirst(pattern, capture.hit, format!"(?P<%s>%s)"(paramName, paramPattern));
    }

    // Finally, second pass where wildcard placeholders are swapped for their regex pattern.
    pattern = replaceAll(pattern, ctRegex!(`--<<MULTI_SEGMENT>>--`), ".*");
    pattern = replaceAll(pattern, ctRegex!(`--<<SINGLE_SEGMENT>>--`), "[^/]+");
    pattern = replaceAll(pattern, ctRegex!(`--<<SINGLE_CHAR>>--`), "[^/]");

    // Add anchors to start and end of string.
    pattern = "^" ~ pattern ~ "$";

    return regex(pattern);
}

unittest {
    import std.format : format;

    void assertMatches(string pattern, string[] examples) {
        if (examples.length == 0) assert(false, "No examples.");
        auto r = compilePathPattern(pattern);
        foreach (example; examples) {
            auto captures = matchFirst(example, r);
            assert(!captures.empty, format!"Example \"%s\" doesn't match pattern: \"%s\"."(example, pattern));
        }
    }

    void assertNotMatches(string pattern, string[] examples) {
        if (examples.length == 0) assert(false, "No examples.");
        auto r = compilePathPattern(pattern);
        foreach (example; examples) {
            auto captures = matchFirst(example, r);
            assert(captures.empty, format!"Example \"%s\" matches pattern: \"%s\"."(example, pattern));
        }
    }

    // Test multi-segment wildcard patterns.
    assertMatches("/users/**", [
        "/users/andrew",
        "/users/",
        "/users/123",
        "/users/123/john"
    ]);
    assertNotMatches("/users/**", [
        "/user",
        "/users",
        "/user-not"
    ]);

    // Test single-segment wildcard patterns.
    assertMatches("/users/*", [
        "/users/andrew",
        "/users/john",
        "/users/wilson",
        "/users/123"
    ]);
    assertNotMatches("/users/*", [
        "/users",
        "/users/",
        "/users/andrew/john",
        "/user"
    ]);

    // Test single-char wildcard patterns.
    assertMatches("/data?", ["/datax", "/datay", "/dataa"]);
    assertNotMatches("/data?", ["/data/x", "/dataxy", "/data"]);

    // Test complex combined patterns.
    assertMatches("/users/{userId}/*/settings/**", [
        "/users/123/username/settings/abc/123",
        "/users/john/pw/settings/test"
    ]);
    assertNotMatches("/users/{userId}/*/settings/**", [
        "/users",
        "/users/settings/123",
        "/users/andrew",
        "/users/john/pw/settings"
    ]);

    // Test path param patterns.
    assertMatches("/users/{userId:int}", ["/users/123", "/users/001", "/users/-42"]);
    assertNotMatches("/users/{userId:int}", ["/users/andrew", "/users", "/users/-", "/users/123a3"]);
    assertMatches("/{path:string}", ["/andrew", "/john"]);
    assertMatches("/digit/{d:[0-9]}", ["/digit/0", "/digit/8"]);
    assertNotMatches("/digit/{d:[0-9]}", ["/digit", "/digit/a", "/digit/123"]);
    
    // Test path param named capture groups.
    auto r1 = compilePathPattern("/users/{userId:int}/settings/{settingName:string}");
    auto m = matchFirst("/users/123/settings/brightness", r1);
    assert(!m.empty);
    assert(m["userId"] == "123");
    assert(m["settingName"] == "brightness");
}
