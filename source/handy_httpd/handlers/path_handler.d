/**
 * This module defines a [PathHandler] that delegates handling of requests to
 * other handlers based on the request's HTTP verb (GET, POST, etc.), and its
 * path.
 */
module handy_httpd.handlers.path_handler;

import http_primitives;
import path_matcher;
import slf4d;
import std.typecons;

/// Internal struct holding details about a handler mapping.
private struct HandlerMapping {
    /// The handler that will handle requests that match this mapping.
    HttpRequestHandler handler;
    /// A bitmask with bits enabled for the HTTP methods that this mapping matches to.
    immutable ushort methodsMask;
    /// A list of string patterns that this mapping matches to.
    immutable(string[]) patterns;
}

/**
 * A request handler that maps incoming requests to a particular handler based
 * on the request's URL path and/or HTTP method (GET, POST, etc.).
 *
 * Use the various overloaded versions of the `addMapping(...)` method to add
 * handlers to this path handler. When handling requests, this path handler
 * will look for matches deterministically in the order you add them. Therefore,
 * adding mappings with conflicting or duplicate paths will cause the first one
 * to always be called.
 *
 * Path patterns should be defined according to the rules from the path-matcher
 * library, found here: https://github.com/andrewlalis/path-matcher
 */
class PathHandler : HttpRequestHandler {
    /// The internal list of all mapped handlers.
    private HandlerMapping[] mappings;

    /// The handler to use when no mapping is found for a request.
    private HttpRequestHandler notFoundHandler;

    /**
     * Constructs a new path handler with initially no mappings, and a default
     * notFoundHandler that simply sets a 404 status.
     */
    this() {
        this.mappings = [];
        this.notFoundHandler = wrapHandler((ref HttpRequest req, ref HttpResponse resp) {
            resp.status = HttpStatus.NOT_FOUND;
        });
    }

    /**
     * Adds a mapping to this handler, such that requests which match the given
     * method and pattern will be handed off to the given handler.
     *
     * Overloaded variations of this method are defined for your convenience,
     * which allow you to add a mapping for multiple HTTP methods and/or path
     * patterns.
     *
     * Params:
     *   method = The HTTP method to match against.
     *   pattern = The path pattern to match against. See https://github.com/andrewlalis/path-matcher
     *             for more details on the pattern's format.
     *   handler = The handler that will handle matching requests.
     * Returns: This path handler, for method chaining.
     */
    PathHandler addMapping(Method method, string pattern, HttpRequestHandler handler) {
        this.mappings ~= HandlerMapping(handler, method, [pattern]);
        return this;
    }
    ///
    PathHandler addMapping(Method[] methods, string pattern, HttpRequestHandler handler) {
        this.mappings ~= HandlerMapping(handler, createMethodMask(methods), [pattern]);
        return this;
    }
    ///
    PathHandler addMapping(Method method, string[] patterns, HttpRequestHandler handler) {
        this.mappings ~= HandlerMapping(handler, method, patterns.idup);
        return this;
    }
    ///
    PathHandler addMapping(Method[] methods, string[] patterns, HttpRequestHandler handler) {
        this.mappings ~= HandlerMapping(handler, createMethodMask(methods), patterns.idup);
        return this;
    }
    ///
    PathHandler addMapping(string pattern, HttpRequestHandler handler) {
        this.mappings ~= HandlerMapping(handler, ushort.max, [pattern]);
        return this;
    }
    ///
    PathHandler addMapping(F)(Method method, string pattern, F func) if (isHttpRequestHandler!F) {
        this.mappings ~= HandlerMapping(wrapHandler(func), method, [pattern]);
        return this;
    }
    ///
    PathHandler addMapping(F)(string pattern, F func) if (isHttpRequestHandler!F) {
        this.mappings ~= HandlerMapping(wrapHandler(func), methodMaskFromAll(), [pattern]);
        return this;
    }
    
    /**
     * Sets the handler that will be called for requests that don't match any
     * pre-configured mappings.
     * Params:
     *   handler = The handler to use.
     * Returns: This path handler, for method chaining.
     */
    PathHandler setNotFoundHandler(HttpRequestHandler handler) {
        if (handler is null) throw new Exception("Cannot set PathHandler's notFoundHandler to null.");
        this.notFoundHandler = handler;
        return this;
    }

    /**
     * Handles a request by looking for a mapped handler whose method and pattern
     * match the request's, and letting that handler handle the request. If no
     * match is found, the notFoundHandler will take care of it.
     * Params:
     *   ctx = The request context.
     */
    void handle(ref HttpRequest request, ref HttpResponse response) {
        HttpRequestHandler mappedHandler = findMappedHandler(request);
        if (mappedHandler !is null) {
            mappedHandler.handle(request, response);
        } else {
            notFoundHandler.handle(request, response);
        }
    }

    /**
     * Finds the handler to use to handle a given request, using our list of
     * pre-configured mappings.
     * Params:
     *   request = The request to find a handler for.
     * Returns: The handler that matches the request, or null if none is found.
     */
    private HttpRequestHandler findMappedHandler(ref HttpRequest request) {
        foreach (HandlerMapping mapping; mappings) {
            if ((mapping.methodsMask & request.method) > 0) {
                foreach (string pattern; mapping.patterns) {
                    PathMatchResult result = matchPath(request.url, pattern);
                    if (result.matches) {
                        debugF!"Found matching handler for %s %s: %s via pattern \"%s\""(
                            request.method,
                            request.url,
                            mapping.handler,
                            pattern
                        );
                        foreach (PathParam param; result.pathParams) {
                            // request.pathParams[param.name] = param.value;
                            // TODO: Add some sort of request context data we can write extra stuff to.
                        }
                        return mapping.handler;
                    }
                }
            }
        }
        debugF!("No handler found for %s %s.")(request.method, request.url);
        return null;
    }
}

// Test PathHandler.setNotFoundHandler
unittest {
    import std.exception;
    auto handler = new PathHandler();
    assertThrown!Exception(handler.setNotFoundHandler(null));
    auto notFoundHandler = toHandler((ref ctx) {
        ctx.response.status = HttpStatus.NOT_FOUND;
    });
    assertNotThrown!Exception(handler.setNotFoundHandler(notFoundHandler));
}

// Test PathHandler.handle
unittest {
    import handy_httpd.util.builders;
    import handy_httpd.components.responses;
    PathHandler handler = new PathHandler()
        .addMapping(Method.GET, "/home", (ref ctx) {ctx.response.okResponse();})
        .addMapping(Method.GET, "/users", (ref ctx) {ctx.response.okResponse();})
        .addMapping(Method.GET, "/users/:id:ulong", (ref ctx) {ctx.response.okResponse();})
        .addMapping(Method.GET, "/api/*", (ref ctx) {ctx.response.okResponse();});

    HttpRequestContext generateHandledCtx(Method method, string url) {
        auto ctx = buildCtxForRequest(method, url);
        handler.handle(ctx);
        return ctx;
    }

    assert(generateHandledCtx(Method.GET, "/home").response.status == HttpStatus.OK);
    assert(generateHandledCtx(Method.GET, "/home-not-exists").response.status == HttpStatus.NOT_FOUND);
    assert(generateHandledCtx(Method.GET, "/users").response.status == HttpStatus.OK);
    assert(generateHandledCtx(Method.GET, "/users/34").response.status == HttpStatus.OK);
    assert(generateHandledCtx(Method.GET, "/users/34").request.getPathParamAs!ulong("id") == 34);
    assert(generateHandledCtx(Method.GET, "/api/test").response.status == HttpStatus.OK);
    assert(generateHandledCtx(Method.GET, "/api/test/bleh").response.status == HttpStatus.NOT_FOUND);
    assert(generateHandledCtx(Method.GET, "/api").response.status == HttpStatus.NOT_FOUND);
    assert(generateHandledCtx(Method.GET, "/").response.status == HttpStatus.NOT_FOUND);
}
