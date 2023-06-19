/+ dub.sdl:
    dependency "handy-httpd" path="../../"
    dependency "streams" version="~>3.4.0"
+/
module file_test_server;

import handy_httpd;
import slf4d;
import slf4d.default_provider;
import handy_httpd.handlers.path_delegating_handler;
import streams;

import std.path;
import std.file;
import std.string;

void main() {
    auto provider = new shared DefaultProvider(true, Levels.TRACE);
    configureLoggingProvider(provider);

    ServerConfig config = ServerConfig.defaultValues();
    config.workerPoolSize = 3;
    config.port = 8080;

    PathDelegatingHandler handler = new PathDelegatingHandler();

    handler.addMapping("GET", "/ready", (ref HttpRequestContext ctx) {
        ctx.response.status = HttpStatus.OK;
    });

	handler.addMapping("POST", "/upload", (ref HttpRequestContext ctx) {
		debug_("Receiving uploaded file...");
		debugF!"Headers: %s"(ctx.request.headers);
		
		ulong size = ctx.request.readBodyToFile("uploaded-file.txt", true);
		debugF!"Received %d bytes"(size);
		ctx.response.writeBodyString("Thank you!");
	});
	
	handler.addMapping("GET", "/source", (ref HttpRequestContext ctx) {
		debug_("Sending app source text.");
		const fileToDownload = "server.d";
		auto sIn = FileInputStream(toStringz(fileToDownload));
		ctx.response.writeBody(sIn, getSize(fileToDownload), "text/plain");
	});

    handler.addMapping("POST", "/shutdown", (ref HttpRequestContext ctx) {
        debug_("Shutting down...");
        ctx.server.stop();
    });

    HttpServer server = new HttpServer(handler, config);
    server.start();
}
