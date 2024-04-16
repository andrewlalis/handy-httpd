/+ dub.sdl:
    dependency "handy-httpd" path="../../"
+/
module file_test_server;

import handy_httpd;
import handy_httpd.components.context;
import handy_httpd.handlers.path_handler;
import http_primitives;
import slf4d;
import slf4d.default_provider;

import std.stdio;
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
        .addMapping(Method.GET, "/ready", wrapHandler((ref HttpResponse resp) {
            warn("Sending ready status!");
            resp.status = HttpStatus.OK;
        }))
        .addMapping(Method.POST, "/upload", wrapHandler((ref HttpRequest req, ref HttpResponse resp) {
            warn("Receiving uploaded file...");
            warnF!"Headers: %s"(req.headers);
            ubyte[] bytes = req.readBodyAsBytes();
            std.file.write("uploaded-file.txt", bytes);
            warnF!"Received %d bytes."(bytes.length);
            resp.writeBodyString("Thank you!");
        }))
        .addMapping(Method.GET, "/source", wrapHandler((ref HttpResponse resp) {
            debug_("Sending app source text.");
            File file = File("server.d");
            resp.writeBody(file.byChunk(4096), file.size, "text/plain");
        }))
        .addMapping(Method.POST, "/shutdown", wrapHandler((ref HttpResponse resp) {
            debug_("Shutting down...");
            REQUEST_CONTEXT.server.stop();
        }));

    HttpServer server = new HttpServer(handler, config);
    server.start();
}
