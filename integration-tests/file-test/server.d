/+ dub.sdl:
    dependency "handy-httpd" path="../../"
+/
module file_test_server;

import handy_httpd;
import handy_httpd.handlers.path_handler;
import slf4d;
import slf4d.default_provider;
import streams;

import std.path;
import std.file;
import std.string;

void main() {
    auto provider = new DefaultProvider(true, Levels.TRACE);
    configureLoggingProvider(provider);

    ServerConfig config;
    config.workerPoolSize = 3;
    config.port = 8080;

    PathHandler handler = new PathHandler()
        .addMapping(Method.GET, "/ready", (ref HttpRequestContext ctx) {
            ctx.response.status = HttpStatus.OK;
        })
        .addMapping(Method.POST, "/upload", (ref HttpRequestContext ctx) {
            debug_("Receiving uploaded file...");
            debugF!"Headers: %s"(ctx.request.headers);
            
            ulong size = ctx.request.readBodyToFile("uploaded-file.txt", true);
            debugF!"Received %d bytes"(size);
            ctx.response.writeBodyString("Thank you!");
        })
        .addMapping(Method.GET, "/source", (ref HttpRequestContext ctx) {
            debug_("Sending app source text.");
            const fileToDownload = "server.d";
            auto sIn = FileInputStream(toStringz(fileToDownload));
            ctx.response.writeBody(sIn, getSize(fileToDownload), "text/plain");
        })
        .addMapping(Method.POST, "/shutdown", (ref HttpRequestContext ctx) {
            debug_("Shutting down...");
            ctx.server.stop();
        });

    HttpServer server = new HttpServer(handler, config);
    server.start();
}
