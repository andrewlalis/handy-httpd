#!/usr/bin/env dub
/+ dub.sdl:
    dependency "handy-httpd" path="../../"
+/
import handy_httpd;
import slf4d;

void main() {
    // First we set up our server's configuration, using mostly default values,
    // but we'll tweak a few settings, and to be extra clear, we explicitly set
    // the port to 8080 (even though that's the default).
    ServerConfig cfg = ServerConfig.defaultValues();
    cfg.workerPoolSize = 5;
    cfg.port = 8080;

    // Now we construct a new instance of the HttpServer class, and provide it
    // a lambda function to use when handling requests.
    new HttpServer((ref ctx) {
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
    }, cfg).start(); // Calling start actually start's the server's main loop.
}
