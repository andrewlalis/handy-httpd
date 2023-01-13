#!/usr/bin/env dub
/+ dub.sdl:
    dependency "handy-httpd" path="../../"
+/
import handy_httpd;

void main() {
    ServerConfig cfg = ServerConfig.defaultValues();
    cfg.workerPoolSize = 5;
    cfg.port = 8080;
    cfg.verbose = true;
    new HttpServer((ref ctx) {
        if (ctx.request.url == "/stop") {
            ctx.response.writeBody("Shutting down the server.");
            ctx.server.stop();
        } else if (ctx.request.url == "/hello") {
            ctx.response.writeBody("Hello world!");
        } else {
            ctx.response.notFound();
        }
    }, cfg).start();
}
