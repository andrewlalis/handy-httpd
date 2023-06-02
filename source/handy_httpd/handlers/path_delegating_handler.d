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
 * Mapping a request to a handler requires both a matching URL, and an
 * acceptable HTTP method. For example, a handler may be registered to handle
 * GET requests to "/home", or POST and PUT requests to "/users".
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
import std.typecons;

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

    this() {
        this.handlerMappings = [];
        this.notFoundHandler = toHandler((ref ctx) { notFoundResponse(ctx.response); });
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
     * `[]` as the `methods` argument.
     * ```d
     * new PathDelegatingHandler()
     *     .addMapping([], "/users/{name}", myHandler);
     * ```
     *
     * Params:
     *   methods = The methods that the handler accepts.
     *   pathPattern = The path pattern the handler accepts.
     *   handler = The handler to handle requests.
     * Returns: This path delegating handler.
     */
    public PathDelegatingHandler addMapping(string[] methods, string pathPattern, HttpRequestHandler handler) {
        import std.algorithm : map, sort, uniq;
        import std.string : format, toUpper;
        import std.array : array;

        if (handler is null) throw new Exception("Cannot add a mapping for a null handler.");

        ushort methodsMask = methodMaskFromNames(methods);
        if (methods.length == 0) methodsMask = methodMaskFromAll();
        foreach (mapping; this.handlerMappings) {
            // TODO: Actually parse and check if path patterns overlap.
            if (mapping.pathPattern == pathPattern && (mapping.methodsMask & methodsMask) > 0) {
                throw new Exception(
                    format!"A mapping already exists for methods %s and path %s."(methods, pathPattern)
                );
            }
        }
        auto t = compilePathPattern(pathPattern);
        this.handlerMappings ~= HandlerMapping(
            pathPattern,
            methodsMask,
            handler,
            cast(immutable) t.regex,
            cast(immutable) t.pathParamNames
        );
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
        return this.addMapping(new string[0], pathPattern, handler);
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
        return this.addMapping(new string[0], pathPattern, handler);
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
            notFoundResponse(ctx.response);
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
            if ((mapping.methodsMask & ctx.request.method) > 0) {
                // Now check if the URL matches.
                log.traceF!"Checking if pattern %s matches url %s"(mapping.pathPattern, ctx.request.url);
                Captures!string captures = matchFirst(ctx.request.url, mapping.compiledPattern);
                if (!captures.empty) {
                    log.debugF!"Found matching handler for %s %s (pattern: \"%s\")"(
                        ctx.request.method,
                        ctx.request.url,
                        mapping.pathPattern
                    );
                    log.traceF!"Captures: %s"(captures);
                    foreach (paramName; mapping.pathParamNames) {
                        ctx.request.pathParams[paramName] = captures[paramName];
                    }
                    mapping.handler.handle(ctx);
                    return; // Exit once the request is handled.
                }
            }
        }
        log.debugF!"No matching handler found for %s %s"(ctx.request.method, ctx.request.url);
        notFoundHandler.handle(ctx);
    }

    unittest {
        import handy_httpd.server;
        import handy_httpd.components.responses;
        import handy_httpd.util.builders;

        // import slf4d;
        // import slf4d.default_provider;
        // auto logProvider = new shared DefaultProvider();
        // logProvider.getLoggerFactory().setRootLevel(Levels.TRACE);
        // configureLoggingProvider(logProvider);

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
            auto ctx = buildCtxForRequest(methodFromName(method), url);
            handler.handle(ctx);
            return ctx;
        }

        assert(generateHandledCtx("GET", "/home").response.status == HttpStatus.OK);
        assert(generateHandledCtx("GET", "/home-not-exists").response.status == HttpStatus.NOT_FOUND);
        assert(generateHandledCtx("GET", "/users").response.status == HttpStatus.OK);
        assert(generateHandledCtx("GET", "/users/34").response.status == HttpStatus.OK);
        assert(generateHandledCtx("GET", "/users/34").request.getPathParamAs!int("id") == 34);
        assert(generateHandledCtx("GET", "/api/test").response.status == HttpStatus.OK);
        assert(generateHandledCtx("GET", "/api/test/bleh").response.status == HttpStatus.NOT_FOUND);
        assert(generateHandledCtx("GET", "/api").response.status == HttpStatus.NOT_FOUND);
        assert(generateHandledCtx("GET", "/").response.status == HttpStatus.NOT_FOUND);
    }
}

/** 
 * Represents a mapping of a specific request handler to a subset of URLs
 * and/or request methods.
 */
private struct HandlerMapping {
    /** 
     * The original pattern used to match against URLs.
     */
    private immutable string pathPattern;

    /** 
     * A bitmask that contains a 1 for each HTTP method this mapping applies to.
     */
    private immutable ushort methodsMask;

    /** 
     * The handler to apply to requests whose URL and method match this
     * mapping's path pattern and methods list.
     */
    private HttpRequestHandler handler;

    /** 
     * The compiled regular expression used to match URLs.
     */
    private immutable Regex!char compiledPattern;

    /** 
     * A cached list of all expected path parameter names, which are used to
     * get path params from a regex match.
     */
    private immutable string[] pathParamNames;
}

/** 
 * Compiles a "path pattern" into a Regex that can be used at runtime for
 * matching against request URLs. For the path pattern specification, please
 * see this module's documentation.
 * Params:
 *   pattern = The path pattern to compile.
 * Returns: A tuple containing a regex to match the given pattern, and a list
 * of path parameter names that were parsed from the pattern.
 */
public Tuple!(Regex!char, "regex", string[], "pathParamNames") compilePathPattern(string pattern) {
    import std.algorithm : canFind;
    import std.format : format;
    import std.array : replaceFirst;

    auto multiSegmentWildcardRegex = ctRegex!(`/\*\*`);
    auto singleSegmentWildcardRegex = ctRegex!(`/\*`);
    auto singleCharWildcardRegex = ctRegex!(`\?`);
    auto pathParamRegex = ctRegex!(`\{(?P<name>[a-zA-Z][a-zA-Z0-9_-]*)(?::(?P<type>[^}]+))?\}`);

    string originalPattern = pattern;
    auto log = getLogger();

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
            } else if (paramType == "uint") {
                paramPattern = "[0-9]+";
            } else if (paramType == "string") {
                paramPattern = `\w+`;
            } else {
                paramPattern = paramType;
            }
        }
        pattern = replaceFirst(pattern, capture.hit, format!"(?P<%s>%s)"(paramName, paramPattern));
    }

    // Finally, second pass where wildcard placeholders are swapped for their regex pattern.
    pattern = replaceAll(pattern, ctRegex!(`--<<MULTI_SEGMENT>>--`), `(?:/[^/]+)*/?`);
    pattern = replaceAll(pattern, ctRegex!(`--<<SINGLE_SEGMENT>>--`), `/[^/]+`);
    pattern = replaceAll(pattern, ctRegex!(`--<<SINGLE_CHAR>>--`), `[^/]`);

    // Add anchors to start and end of string.
    pattern = "^" ~ pattern ~ "$";
    log.debugF!"Compiled path pattern \"%s\" to regex \"%s\""(originalPattern, pattern);

    return tuple!("regex", "pathParamNames")(regex(pattern), pathParamNames);
}

unittest {
    import std.format : format;

    void assertMatches(string pattern, string[] examples) {
        if (examples.length == 0) assert(false, "No examples.");
        auto r = compilePathPattern(pattern).regex;
        foreach (example; examples) {
            auto captures = matchFirst(example, r);
            assert(
                !captures.empty,
                format!"Example \"%s\" doesn't match pattern: \"%s\". Regex: %s"(example, pattern, r)
            );
        }
    }

    void assertNotMatches(string pattern, string[] examples) {
        if (examples.length == 0) assert(false, "No examples.");
        auto r = compilePathPattern(pattern).regex;
        foreach (example; examples) {
            auto captures = matchFirst(example, r);
            assert(
                captures.empty,
                format!"Example \"%s\" matches pattern: \"%s\". Regex: %s"(example, pattern, r)
            );
        }
    }

    // Test multi-segment wildcard patterns.
    assertMatches("/users/**", [
        "/users/andrew",
        "/users/",
        "/users",
        "/users/123",
        "/users/123/john"
    ]);
    assertNotMatches("/users/**", [
        "/user",
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
        "/users/john/pw/settings/test",
        "/users/123/username/settings"
    ]);
    assertNotMatches("/users/{userId}/*/settings/**", [
        "/users",
        "/users/settings/123",
        "/users/andrew"
    ]);

    // Test path param patterns.
    assertMatches("/users/{userId:int}", ["/users/123", "/users/001", "/users/-42"]);
    assertNotMatches("/users/{userId:int}", ["/users/andrew", "/users", "/users/-", "/users/123a3"]);
    assertMatches("/{path:string}", ["/andrew", "/john"]);
    assertMatches("/digit/{d:[0-9]}", ["/digit/0", "/digit/8"]);
    assertNotMatches("/digit/{d:[0-9]}", ["/digit", "/digit/a", "/digit/123"]);
    
    // Test path param named capture groups.
    auto t = compilePathPattern("/users/{userId:int}/settings/{settingName:string}");
    assert(t.pathParamNames == ["userId", "settingName"]);
    auto m = matchFirst("/users/123/settings/brightness", t.regex);
    assert(!m.empty);
    assert(m["userId"] == "123");
    assert(m["settingName"] == "brightness");
}
