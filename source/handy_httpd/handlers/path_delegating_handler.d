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
 * GET requests to "/home", or POST and PUT requests to "/users". A handler may
 * even be registered to multiple paths.
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
 * An exception that's thrown if an invalid handler mapping is defined by a
 * user of the PathDelegatingHandler class.
 */
class HandlerMappingException : Exception {
    import std.exception : basicExceptionCtors;
    mixin basicExceptionCtors;
}

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
     *     .addMapping([Method.GET, Method.PATCH], "/users/{name}", myHandler);
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
     *   pathPatterns = The path patterns the handler accepts.
     *   handler = The handler to handle requests.
     * Returns: This path delegating handler.
     */
    public PathDelegatingHandler addMapping(Method[] methods, string[] pathPatterns, HttpRequestHandler handler) {
        import std.string : format, join;

        if (handler is null) {
            throw new HandlerMappingException("Cannot add a mapping for a null handler.");
        }

        if (pathPatterns is null || pathPatterns.length < 1) {
            pathPatterns = ["**"]; // If no path patterns are given, match anything.
        }

        immutable ushort methodsMask = (methods !is null && methods.length > 0)
            ? methodMaskFromMethods(methods)
            : methodMaskFromAll();
        // TODO: Check that there's no unintended conflict with another mapping.
        Regex!(char)[] regexes = new Regex!(char)[pathPatterns.length];
        string[][] pathParamNames = new string[][pathPatterns.length];
        foreach (size_t i, string pathPattern; pathPatterns) {
            auto t = compilePathPattern(pathPattern);
            regexes[i] = t.regex;
            pathParamNames[i] = t.pathParamNames;
        }
        import std.algorithm : map;
        import std.array : array;
        this.handlerMappings ~= HandlerMapping(
            pathPatterns.idup,
            methodsMask,
            handler,
            cast(immutable Regex!(char)[]) regexes,
            pathParamNames.map!(a => a.idup).array.idup // Dirty hack to turn string[][] into immutable.
        );
        return this;
    }

    unittest {
        import std.exception;
        // Check that a null handler results in an exception.
        HttpRequestHandler nullHandler = null;
        assertThrown!HandlerMappingException(
            new PathDelegatingHandler().addMapping([Method.GET], ["/**"], nullHandler)
        );
        // Check that if no methods are given, then all methods are added to the method mask.
        HttpRequestHandler dummyHandler = noOpHandler();
        Method[] nullMethods = null;
        PathDelegatingHandler p1 = new PathDelegatingHandler()
            .addMapping([], ["/**"], dummyHandler)
            .addMapping(nullMethods, ["/**"], dummyHandler);
        assert(p1.handlerMappings.length == 2);
        assert(p1.handlerMappings[0].methodsMask == methodMaskFromAll());
        assert(p1.handlerMappings[1].methodsMask == methodMaskFromAll());
        // Check that if no path patterns are given, then the all path pattern is given.
        string[] nullPathPatterns = null;
        PathDelegatingHandler p2 = new PathDelegatingHandler()
            .addMapping([Method.GET], new string[0], dummyHandler)
            .addMapping([Method.GET], nullPathPatterns, dummyHandler);
        assert(p2.handlerMappings.length == 2);
        assert(p2.handlerMappings[0].pathPatterns == ["**"]);
        assert(p2.handlerMappings[1].pathPatterns == ["**"]);
    }

    public PathDelegatingHandler addMapping(Method[] methods, string[] pathPatterns, HttpRequestHandlerFunction fn) {
        return this.addMapping(methods, pathPatterns, toHandler(fn));
    }

    public PathDelegatingHandler addMapping(Method method, string[] pathPatterns, HttpRequestHandler handler) {
        Method[1] arr = [method];
        return this.addMapping(arr, pathPatterns, handler);
    }

    public PathDelegatingHandler addMapping(Method method, string[] pathPatterns, HttpRequestHandlerFunction fn) {
        return this.addMapping(method, pathPatterns, toHandler(fn));
    }

    public PathDelegatingHandler addMapping(Method[] methods, string pathPattern, HttpRequestHandler handler) {
        string[1] arr = [pathPattern];
        return this.addMapping(methods, arr, handler);
    }

    public PathDelegatingHandler addMapping(Method method, string pathPattern, HttpRequestHandler handler) {
        Method[1] m = [method];
        string[1] p = [pathPattern];
        return this.addMapping(m, p, handler);
    }

    public PathDelegatingHandler addMapping(Method method, string pathPattern, HttpRequestHandlerFunction fn) {
        return this.addMapping(method, pathPattern, toHandler(fn));
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
        foreach (mapping; handlerMappings) {
            if ((mapping.methodsMask & ctx.request.method) > 0) {
                traceF!"Checking if patterns %s match url %s"(mapping.pathPatterns, ctx.request.url);
                for (size_t patternIdx = 0; patternIdx < mapping.pathPatterns.length; patternIdx++) {
                    string pathPattern = mapping.pathPatterns[patternIdx];
                    immutable Regex!char compiledPattern = mapping.compiledPatterns[patternIdx];
                    immutable string[] paramNames = mapping.pathParamNames[patternIdx];
                    Captures!string captures = matchFirst(ctx.request.url, compiledPattern);
                    if (!captures.empty) {
                        debugF!"Found matching handler for %s %s (pattern: \"%s\")"(
                            ctx.request.method,
                            ctx.request.url,
                            pathPattern
                        );
                        traceF!"Captures: %s"(captures);
                        foreach (string paramName; paramNames) {
                            ctx.request.pathParams[paramName] = captures[paramName];
                        }
                        ctx.request.pathPattern = pathPattern;
                        mapping.handler.handle(ctx);
                        return;
                    }
                }
            }
        }
        debugF!"No matching handler found for %s %s"(ctx.request.method, ctx.request.url);
        notFoundHandler.handle(ctx);
    }

    unittest {
        import handy_httpd.server;
        import handy_httpd.components.responses;
        import handy_httpd.util.builders;

        auto handler = new PathDelegatingHandler()
            .addMapping(Method.GET, "/home", (ref ctx) {ctx.response.okResponse();})
            .addMapping(Method.GET, "/users", (ref ctx) {ctx.response.okResponse();})
            .addMapping(Method.GET, "/users/{id}", (ref ctx) {ctx.response.okResponse();})
            .addMapping(Method.GET, "/api/*", (ref ctx) {ctx.response.okResponse();});

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
struct HandlerMapping {
    /** 
     * The original pattern(s) used to match against URLs.
     */
    immutable string[] pathPatterns;

    /** 
     * A bitmask that contains a 1 for each HTTP method this mapping applies to.
     */
    immutable ushort methodsMask;

    /** 
     * The handler to apply to requests whose URL and method match this
     * mapping's path pattern and methods list.
     */
    HttpRequestHandler handler;

    /** 
     * The compiled regular expression(s) used to match URLs.
     */
    immutable Regex!(char)[] compiledPatterns;

    /** 
     * A cached list of all expected path parameter names, which are used to
     * get path params from a regex match. There is one list of path parameter
     * names for each pathPattern.
     */
    immutable string[][] pathParamNames;
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
            throw new HandlerMappingException(
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
    debugF!"Compiled path pattern \"%s\" to regex \"%s\""(originalPattern, pattern);

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
