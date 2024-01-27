#!/usr/bin/env dub
/+ dub.sdl:
    dependency "handy-httpd" path="../"
+/

/**
 * This example shows you how to use the `PathHandler` to route requests to
 * specific handlers based on their path, and includes examples which use
 * path variables to extract information from parts of the request's URL path.
 *
 * In this example, we'll build a simple API that stores a list of names, and
 * use it to showcase the features of the PathHandler.
 *
 * To get the list of names: `curl http://localhost:8080/names`
 *
 * To add a name to the list: `curl -X POST http://localhost:8080/names?name=john`
 *
 * To get a name by its index: `curl http://localhost:8080/names/0`
 */
module examples.path_handler;

import handy_httpd;
import handy_httpd.handlers.path_handler;
import std.json;

/// The global list of names that this example uses.
__gshared string[] names = [];

void main(string[] args) {
    ServerConfig cfg;
    if (args.length > 1) {
        import std.conv;
        cfg.port = args[1].to!ushort;
    }

    // We'll use the PathHandler as our server's "root" handler.
    // Handy-Httpd uses composition to add functionality to your server.
    PathHandler pathHandler = new PathHandler();

    // We can add mappings to handler functions or HttpRequestHandler instances.
    pathHandler.addMapping(Method.GET, "/names", &getNames);
    pathHandler.addMapping(Method.POST, "/names", &postName);

    // We can also specify a path variable, which will be extracted by the
    // PathHandler if a request matches this pattern.
    // Notice how we annotate it as a ulong; only unsigned long integers are
    // accepted. "/names/abc" will not match, for example.
    pathHandler.addMapping(Method.GET, "/names/:idx:ulong", &getName);

    new HttpServer(pathHandler, cfg).start();
}

/**
 * Shows all names as a JSON array of strings.
 * Params:
 *   ctx = The request context.
 */
void getNames(ref HttpRequestContext ctx) {
    JSONValue response = JSONValue(string[].init);
    foreach (name; names) {
        response.array ~= JSONValue(name);
    }
    ctx.response.writeBodyString(response.toString(), "application/json");
}

/**
 * Adds a name to the global list of names, if one is provided as a query
 * parameter with the key "name".
 * Params:
 *   ctx = The request context.
 */
void postName(ref HttpRequestContext ctx) {
    string name = ctx.request.queryParams.getFirst("name").orElse(null);
    if (name is null || name.length == 0) {
        ctx.response.setStatus(HttpStatus.BAD_REQUEST);
        ctx.response.writeBodyString("Missing name.");
        return;
    }
    names ~= name;
}

/**
 * Gets a specific name by its index in the global list of names.
 * Params:
 *   ctx = The request context.
 */
void getName(ref HttpRequestContext ctx) {
    ulong idx = ctx.request.getPathParamAs!ulong("idx");
    if (idx >= names.length) {
        ctx.response.setStatus(HttpStatus.NOT_FOUND);
        ctx.response.writeBodyString("No name with that index was found.");
        return;
    }
    ctx.response.writeBodyString(names[idx]);
}
