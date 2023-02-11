#!/usr/bin/env dub
/+ dub.sdl:
    dependency "handy-httpd" path="../../"
+/
import handy_httpd;
import handy_httpd.handlers.file_resolving_handler;

void main() {
    auto handler = new FileResolvingHandler("content");
    new HttpServer(handler).start();
}
