#!/usr/bin/env dub
/+ dub.sdl:
    dependency "handy-httpd" path="../../"
+/
import handy_httpd;
import handy_httpd.handlers.file_resolving_handler;

void main(string[] args) {
    ServerConfig cfg;
    if (args.length > 1) {
        import std.conv;
        cfg.port = args[1].to!ushort;
    }
    new HttpServer(new FileResolvingHandler("content"), cfg).start();
}
