#!/usr/bin/env dub
/+ dub.sdl:
    dependency "handy-httpd" path="../../"
+/
import handy_httpd;
import slf4d;

void main() {
    ServerConfig cfg = ServerConfig.defaultValues();
    cfg.workerPoolSize = 5;
    cfg.port = 8080;
    new HttpServer((ref ctx) {
        if (ctx.request.url == "/stop") {
            ctx.response.writeBodyString("Shutting down the server.");
            ctx.server.stop();
        } else if (ctx.request.url == "/hello") {
            infoF!"Responding to request: %s"(ctx.request.url);
            ctx.response.writeBodyString("Hello world!");
        } else {
            ctx.response.notFound();
        }
    }, cfg).start();
}
