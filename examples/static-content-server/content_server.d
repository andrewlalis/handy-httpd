#!/usr/bin/env dub
/+ dub.sdl:
    dependency "handy-httpd" path="../../"
+/
import handy_httpd;
import handy_httpd.handlers.file_resolving_handler;

void main() {
    ServerConfig cfg = ServerConfig.defaultValues();
    cfg.workerPoolSize = 5;
    cfg.port = 8081;
    cfg.verbose = true;
    auto handler = new FileResolvingHandler("content");
    new HttpServer(handler, cfg).start();
}
