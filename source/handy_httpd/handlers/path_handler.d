/**
 * A work-in-progress module to replace path_delegating_handler with something more efficient.
 */
module handy_httpd.handlers.path_handler;

import handy_httpd.components.handler;
import handy_httpd.components.request;
import handy_httpd.components.response;
import path_matcher;
import slf4d;

private struct HandlerMapping {
    HttpRequestHandler handler;
    immutable ushort methodsMask;
    immutable(string[]) patterns;
}

class PathHandler : HttpRequestHandler {
    private HandlerMapping[] mappings;
    private HttpRequestHandler notFoundHandler;

    this() {
        this.mappings = [];
        this.notFoundHandler = toHandler((ref ctx) { ctx.response.status = HttpStatus.NOT_FOUND; });
    }

    PathHandler addMapping(Method method, string pattern, HttpRequestHandler handler) {
        this.mappings ~= HandlerMapping(handler, method, [pattern]);
        return this;
    }

    PathHandler addMapping(Method[] methods, string pattern, HttpRequestHandler handler) {
        this.mappings ~= HandlerMapping(handler, methodMaskFromMethods(methods), [pattern]);
        return this;
    }

    PathHandler addMapping(Method method, string[] patterns, HttpRequestHandler handler) {
        this.mappings ~= HandlerMapping(handler, method, patterns.idup);
        return this;
    }

    PathHandler addMapping(Method[] methods, string[] patterns, HttpRequestHandler handler) {
        this.mappings ~= HandlerMapping(handler, methodMaskFromMethods(methods), patterns.idup);
        return this;
    }

    void handle(ref HttpRequestContext ctx) {
        foreach (HandlerMapping mapping; mappings) {
            if ((mapping.methodsMask & ctx.request.method) > 0) {
                foreach (string pattern; mapping.patterns) {
                    PathMatchResult result = matchPath(ctx.request.url, pattern);
                    if (result.matches) {
                        debugF!"Found matching handler for %s request to %s: %s"(
                            methodToName(ctx.request.method),
                            ctx.request.url,
                            mapping.handler
                        );
                        string[string] paramsMap;
                        foreach (PathParam param; result.pathParams) {
                            paramsMap[param.name] = param.value;
                        }
                        ctx.request.pathParams = paramsMap;
                        mapping.handler.handle(ctx);
                        return;
                    }
                }
            }
        }
        debug_("No matching handler found. Using notFoundHandler.");
        notFoundHandler.handle(ctx);
    }
}
