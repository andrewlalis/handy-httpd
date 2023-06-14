import slf4d;
import slf4d.default_provider;
import handy_httpd;
import handy_httpd.handlers.path_delegating_handler;
import requests;

import core.thread;

int main() {
	auto provider = new shared DefaultProvider(true, Levels.TRACE);
	configureLoggingProvider(provider);

	HttpServer server = getTestingServer();
	Thread serverThread = new Thread(&server.start);
	serverThread.start();
	scope(exit) {
		server.stop();
		serverThread.join();
	}

	while (!server.isReady()) {
		info("Waiting for server to come online...");
		Thread.sleep(msecs(1));
	}
	info("Testing server is online.");

	testFileUpload();
	
	return 0;
}

void testFileUpload() {
	import std.stdio;
	import std.file;
	auto f = File("sample-files/sample-1.txt", "rb");
	auto content = postContent("http://localhost:8080/upload", f.byChunk(8192), "text/plain");
	assert(std.file.exists("uploaded-file.txt"));
	assert(getSize("uploaded-file.txt") == getSize("sample-files/sample-1.txt"));
}

HttpServer getTestingServer() {
	ServerConfig config = ServerConfig.defaultValues();
	config.workerPoolSize = 3;
	config.port = 8080;

	PathDelegatingHandler handler = new PathDelegatingHandler();
	handler.addMapping("POST", "/upload", (ref HttpRequestContext ctx) {
		ctx.request.readBodyToFile("uploaded-file.txt");
		ctx.response.writeBodyString("Thank you!");
	});

	return new HttpServer(handler, config);
}
