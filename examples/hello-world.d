#!/usr/bin/env dub
/+ dub.sdl:
    dependency "handy-httpd" path="../"
+/

/**
 * A basic example that shows you how to start your server and deal with
 * incoming requests.
 */
module examples.hello_world;

import handy_httpd;
import slf4d;

void main(string[] args) {
    ServerConfig cfg;
    if (args.length > 1) {
        import std.conv;
        cfg.port = args[1].to!ushort;
    }
    new HttpServer((ref HttpRequestContext ctx) {
        // We can inspect the request's URL directly like so:
        if (ctx.request.url == "/stop") {
            ctx.response.writeBodyString("Shutting down the server.");
            ctx.server.stop(); // Calling stop will gracefully shutdown the server.
        } else if (ctx.request.url == "/hello") {
            infoF!"Responding to request: %s"(ctx.request.url);
            ctx.response.writeBodyString("Hello world!");
        } else {
            ctx.response.setStatus(HttpStatus.NOT_FOUND);
        }
    }, cfg).start(); // Calling start actually starts the server's main loop.
}
