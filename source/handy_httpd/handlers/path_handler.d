/**
 * A work-in-progress module to replace path_delegating_handler with something more efficient.
 */
module handy_httpd.handlers.path_handler;

import handy_httpd.components.handler;
import handy_httpd.components.request;

struct HandlerMapping {
    HttpRequestHandler handler;
    immutable ushort methodsMask;
    immutable string[] patterns;
    immutable string[][] pathParamNames;
}

private immutable struct PathParam {
    string name;
    string type;
}

private immutable struct PathPattern {
    string[] segments;
    PathParam[] pathParams;
}

private PathPattern compilePattern(string path) {
    import std.string : split;
    import std.algorithm : filter;
    import std.array : array, appender, Appender;
    string[] segments = split(path, "/")
        .filter!(s => s.length > 0)
        .array;
    Appender!(PathParam[]) pathParamAppender;
    return PathPattern(segments.idup);
}

unittest {
    assert(compilePattern("/test/bleh") == PathPattern(["test", "bleh"]));
    assert(compilePattern("/") == PathPattern([]));
}
