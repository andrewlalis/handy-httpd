#!/usr/bin/env dub
/+ dub.sdl:
    dependency "handy-httpd" path="../"
+/

/**
 * This example shows how you can access a request's headers. Headers are
 * stored as a constant multivalue map of strings in the context's request,
 * so as you can see below, we access them via `ctx.request.headers`.
 */
module examples.using_headers;

import handy_httpd;
import slf4d;
import std.format;

void main(string[] args) {
    ServerConfig cfg;
    if (args.length > 1) {
        import std.conv;
        cfg.port = args[1].to!ushort;
    }
    new HttpServer(&respondWithHeaders, cfg).start();
}

void respondWithHeaders(ref HttpRequestContext ctx) {
    string response = "Headers:\n\n";
    foreach (name, value; ctx.request.headers) {
        response ~= name ~ ": " ~ value ~ "\n";
    }
    if (ctx.request.headers.contains("User-Agent")) {
        string userAgent = ctx.request.headers["User-Agent"];
        response ~= "\nYour user agent is: " ~ userAgent;
    }
    // You could also get the headers via `ctx.request.headers.toString()`,
    // but we used iteration to show other possiblities.
    ctx.response.writeBodyString(response);
}
