/**
 * Notice! This module is deprecated in favor of the [PathHandler].
 *
 * This module defines a [PathDelegatingHandler] that delegates the handling of
 * requests to other handlers, using some matching logic.
 *
 * The [PathDelegatingHandler] works by adding "mappings" to it, which map some
 * properties of HTTP requests, like the URL, method, path parameters, etc, to
 * a particular [HttpRequestHandler].
 *
 * When looking for a matching handler, the PathDelegatingHandler will check
 * its list of handlers in the order that they were added, and the first
 * mapping that matches the request will take it.
 * If a PathDelegatingHandler receives a request for which no mapping matches,
 * then a configurable `notFoundHandler` is called to handle the request. By
 * default, it just applies a basic [HttpStatus.NOT_FOUND] response.
 *
 * ## The Handler Mapping
 *
 * The [HandlerMapping] is a simple struct that maps certain properties of an
 * [HttpRequest] to a particular [HttpRequestHandler]. The PathDelegatingHandler
 * keeps a list of these mappings at runtime, and uses them to determine which
 * handler to delegate to.
 * Each mapping can apply to a certain set of HTTP methods (GET, POST, PATCH,
 * etc.), as well as a set of URL path patterns.
 *
 * Most often, you'll use the [HandlerMappingBuilder] or one of the `addMapping`
 * methods provided by [PathDelegatingHandler].
 *
 * When specifying the set of HTTP methods that a mapping applies to, you may
 * specify a list of methods, a single one, or none at all (which implicitly
 * matches requests with any HTTP method).
 *
 * ### Path Patterns
 *
 * The matching rules for path patterns are inspired by those of Spring
 * Framework's [AntPathMatcher](https://docs.spring.io/spring-framework/docs/current/javadoc-api/org/springframework/util/AntPathMatcher.html)
 * In short, URLs are matched according to the following rules:
 * $(LIST
 *   * `?` matches a single character.
 *   * `*` matches zero or more characters.
 *   * `**` matches zero or more segments in a URL.
 *   * `{value:[a-z]+}` matches a path variable named "value" that conforms to the regular expression `[a-z]+`.
 * )
 */
module handy_httpd.handlers.path_delegating_handler;

import handy_httpd.components.handler;
import handy_httpd.components.request;
import handy_httpd.components.response;
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

    /**
     * Constructs this handler with an empty list of mappings, and a default
     * `notFoundHandler` that just sets a 404 status.
     */
    this() {
        this.handlerMappings = [];
        this.notFoundHandler = toHandler((ref ctx) { ctx.response.status = HttpStatus.NOT_FOUND; });
    }

    /**
     * Adds a new pre-built handler mapping to this handler.
     * Params:
     *   mapping = The mapping to add.
     * Returns: A reference to this handler.
     */
    public PathDelegatingHandler addMapping(HandlerMapping mapping) {
        this.handlerMappings ~= mapping;
        return this;
    }

    /**
     * Obtains a new builder with a fluent interface for constructing a new
     * handler mapping.
     * Returns: The builder.
     */
    public HandlerMappingBuilder addMapping() {
        return new HandlerMappingBuilder(this);
    }

    /// Overload of `addMapping`.
    public PathDelegatingHandler addMapping(Method[] methods, string[] pathPatterns, HttpRequestHandler handler) {
        return this.addMapping()
            .forMethods(methods)
            .forPaths(pathPatterns)
            .withHandler(handler)
            .add();
    }

    /// Overload of `addMapping` which accepts a function handler.
    public PathDelegatingHandler addMapping(Method[] methods, string[] pathPatterns, HttpRequestHandlerFunction fn) {
        return this.addMapping(methods, pathPatterns, toHandler(fn));
    }

    /// Overload of `addMapping` which accepts a single HTTP method.
    public PathDelegatingHandler addMapping(Method method, string[] pathPatterns, HttpRequestHandler handler) {
        Method[1] arr = [method];
        return this.addMapping(arr, pathPatterns, handler);
    }

    /// Overload of `addMapping` which accepts a single HTTP method and function handler.
    public PathDelegatingHandler addMapping(Method method, string[] pathPatterns, HttpRequestHandlerFunction fn) {
        return this.addMapping(method, pathPatterns, toHandler(fn));
    }

    /// Overload of `addMapping` which accepts a single path pattern.
    public PathDelegatingHandler addMapping(Method[] methods, string pathPattern, HttpRequestHandler handler) {
        string[1] arr = [pathPattern];
        return this.addMapping(methods, arr, handler);
    }

    /// Overload of `addMapping` which accepts a single HTTP method and single path pattern.
    public PathDelegatingHandler addMapping(Method method, string pathPattern, HttpRequestHandler handler) {
        Method[1] m = [method];
        string[1] p = [pathPattern];
        return this.addMapping(m, p, handler);
    }

    /// Overload of `addMapping` which accepts a single HTTP method and single path pattern, and a function handler.
    public PathDelegatingHandler addMapping(Method method, string pathPattern, HttpRequestHandlerFunction fn) {
        return this.addMapping(method, pathPattern, toHandler(fn));
    }

    /// Overload of `addMapping` which accepts a single path pattern and applies to all HTTP methods.
    public PathDelegatingHandler addMapping(string pathPattern, HttpRequestHandler handler) {
        return this.addMapping().forPath(pathPattern).withHandler(handler).add();
    }

    /// Overload of `addMapping` which accepts a single path pattern and function handler, and applies to all HTTP methods.
    public PathDelegatingHandler addMapping(string pathPattern, HttpRequestHandlerFunction fn) {
        return this.addMapping().forPath(pathPattern).withHandler(fn).add();
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
            ctx.response.status = HttpStatus.NOT_FOUND;
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
 * A builder for constructing handler mappings using a fluent method interface
 * and support for inlining within the context of a PathDelegatingHandler's
 * methods.
 */
class HandlerMappingBuilder {
    private PathDelegatingHandler pdh;
    private Method[] methods;
    private string[] pathPatterns;
    private HttpRequestHandler handler;

    this() {}
    
    this(PathDelegatingHandler pdh) {
        this.pdh = pdh;
    }

    HandlerMappingBuilder forMethods(Method[] methods) {
        this.methods = methods;
        return this;
    }

    HandlerMappingBuilder forMethod(Method method) {
        this.methods ~= method;
        return this;
    }

    HandlerMappingBuilder forPaths(string[] pathPatterns) {
        this.pathPatterns = pathPatterns;
        return this;
    }

    HandlerMappingBuilder forPath(string pathPattern) {
        this.pathPatterns ~= pathPattern;
        return this;
    }

    HandlerMappingBuilder withHandler(HttpRequestHandler handler) {
        this.handler = handler;
        return this;
    }

    HandlerMappingBuilder withHandler(HttpRequestHandlerFunction fn) {
        this.handler = toHandler(fn);
        return this;
    }

    /**
     * Builds a handler mapping from this builder's configured information.
     * Returns: The handler mapping.
     */
    HandlerMapping build() {
        import std.string : format, join;
        if (handler is null) {
            throw new HandlerMappingException("Cannot create a HandlerMapping with a null handler.");
        }
        if (pathPatterns is null || pathPatterns.length == 0) {
            pathPatterns = ["/**"];
        }
        immutable ushort methodsMask = (methods !is null && methods.length > 0)
            ? methodMaskFromMethods(methods)
            : methodMaskFromAll();
        Regex!(char)[] regexes = new Regex!(char)[pathPatterns.length];
        string[][] pathParamNames = new string[][pathPatterns.length];
        foreach (size_t i, string pathPattern; pathPatterns) {
            auto t = compilePathPattern(pathPattern);
            regexes[i] = t.regex;
            pathParamNames[i] = t.pathParamNames;
        }
        import std.algorithm : map;
        import std.array : array;
        return HandlerMapping(
            pathPatterns.idup,
            methodsMask,
            handler,
            cast(immutable Regex!(char)[]) regexes,
            pathParamNames.map!(a => a.idup).array.idup // Dirty hack to turn string[][] into immutable.
        );
    }

    /**
     * Adds the handler mapping produced by this builder to the
     * PathDelegatingHandler that this builder was initialized with.
     * Returns: The PathDelegatingHandler that the mapping was added to.
     */
    PathDelegatingHandler add() {
        if (pdh is null) {
            throw new HandlerMappingException(
                "Cannot add HandlerMapping to a PathDelegatingHandler when none was used to initialize the builder."
            );
        }
        return pdh.addMapping(this.build());
    }
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

    immutable string originalPattern = pattern;

    // First pass, where we tag all wildcards for replacement on a second pass.
    pattern = replaceAll(pattern, ctRegex!(`/\*\*`), "--<<MULTI_SEGMENT>>--");
    pattern = replaceAll(pattern, ctRegex!(`/\*`), "--<<SINGLE_SEGMENT>>--");
    pattern = replaceAll(pattern, ctRegex!(`\?`), "--<<SINGLE_CHAR>>--");

    // Replace path parameter expressions with regex expressions for them, with named capture groups.
    auto pathParamResults = parsePathParamExpressions(pattern, originalPattern);
    pattern = pathParamResults.pattern;
    string[] pathParamNames = pathParamResults.pathParamNames;

    // Finally, second pass where wildcard placeholders are swapped for their regex pattern.
    pattern = replaceAll(pattern, ctRegex!(`--<<MULTI_SEGMENT>>--`), `(?:/[^/]+)*/?`);
    pattern = replaceAll(pattern, ctRegex!(`--<<SINGLE_SEGMENT>>--`), `/[^/]+`);
    pattern = replaceAll(pattern, ctRegex!(`--<<SINGLE_CHAR>>--`), `[^/]`);

    // Add anchors to start and end of string.
    pattern = "^" ~ pattern ~ "$";
    debugF!"Compiled path pattern \"%s\" to regex \"%s\""(originalPattern, pattern);

    return tuple!("regex", "pathParamNames")(regex(pattern), pathParamNames);
}

/**
 * Helper function that parses and replaces path parameter expressions, like
 * "/users/{userId:uint}", with a regex that captures the path parameter, with
 * support for matching the parameter's type.
 * Params:
 *   pattern = The full URL pattern string.
 *   originalPattern = The original pattern that was provided when compiling.
 * Returns: The URL pattern string, with path parameters replaced with an
 * appropriate regex, and the list of path parameter names.
 */
private Tuple!(string, "pattern", string[], "pathParamNames") parsePathParamExpressions(
    string pattern,
    string originalPattern
) {
    import std.algorithm : canFind;
    import std.string : format;
    import std.array : replaceFirst;

    auto pathParamRegex = ctRegex!(`\{(?P<name>[a-zA-Z][a-zA-Z0-9_-]*)(?::(?P<type>[^}]+))?\}`);
    auto pathParamMatches = matchAll(pattern, pathParamRegex);
    string[] pathParamNames;
    foreach (capture; pathParamMatches) {
        string paramName = capture["name"];
        // Check that the name of this path parameter is unique.
        if (canFind(pathParamNames, paramName)) {
            throw new HandlerMappingException(
                format!"Duplicate path parameter with name \"%s\" in pattern \"%s\"."(paramName, originalPattern)
            );
        }
        pathParamNames ~= paramName;

        string paramType = capture["type"];
        string paramPattern = "[^/]+"; // The default parameter pattern if no type or pattern is defined.
        if (paramType !is null) {
            immutable string[string] DEFAULT_PATH_PARAMETER_TYPE_PATTERNS = [
                "int": `-?[0-9]+`,
                "uint": `[0-9]+`,
                "string": `\w+`,
                "uuid": `[0-9a-fA-F]{8}\b-[0-9a-fA-F]{4}\b-[0-9a-fA-F]{4}\b-[0-9a-fA-F]{4}\b-[0-9a-fA-F]{12}`
            ];
            bool foundMatch = false;
            foreach (typeName, typePattern; DEFAULT_PATH_PARAMETER_TYPE_PATTERNS) {
                if (paramType == typeName) {
                    paramPattern = typePattern;
                    foundMatch = true;
                    break;
                }
            }
            if (!foundMatch) {
                paramPattern = paramType; // No pre-defined type was found, use what the person wrote as a pattern itself.
            }
        }
        pattern = replaceFirst(pattern, capture.hit, format!"(?P<%s>%s)"(paramName, paramPattern));
    }
    return tuple!("pattern", "pathParamNames")(pattern, pathParamNames);
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
