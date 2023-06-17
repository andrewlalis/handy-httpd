import slf4d;
import slf4d.default_provider;
import handy_httpd;
import handy_httpd.handlers.path_delegating_handler;
import requests;
import streams;

import std.stdio;
import std.file;
import std.path;
import std.format;
import std.string;

import core.thread;

int main() {
	auto provider = new shared DefaultProvider(true, Levels.INFO);
	provider.getLoggerFactory().setModuleLevel("streams.types", Levels.WARN);
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
	Thread.sleep(seconds(1));
	logSep();

	testFileUpload();
	Thread.sleep(seconds(1));
	logSep();

	testFileDownload();
	Thread.sleep(seconds(1));
	logSep();

	info("All tests completed.");
	Thread.sleep(msecs(10));
	return 0;
}

/** 
 * Tests uploading a somewhat large file to the server.
 */
void testFileUpload() {
	const originalFile = buildPath("sample-files", "sample-1.txt");
	infoF!"Testing text file upload of size %d bytes."(getSize(originalFile));
	auto f = File(originalFile, "rb");
	auto content = postContent("http://localhost:8080/upload", f.byChunk(8192), "text/plain");
	infoF!"Uploaded file. Got response: %s"(content);
	assert(std.file.exists("uploaded-file.txt"));
	const originalFileSize = getSize(originalFile);
	const newFileSize = getSize("uploaded-file.txt");
	assert(
		originalFileSize == newFileSize,
		format!"Uploaded file size of %d doesn't match original size of %d."(newFileSize, originalFileSize)
	);
}

void testFileDownload() {
	const originalFile = buildPath("source", "app.d");
	infoF!"Testing text file download of size %d bytes."(getSize(originalFile));
	auto content = getContent("http://localhost:8080/source");
	const originalFileSize = getSize(originalFile);
	assert(content.length == originalFileSize);
}

HttpServer getTestingServer() {
	ServerConfig config = ServerConfig.defaultValues();
	config.workerPoolSize = 3;
	config.port = 8080;

	PathDelegatingHandler handler = new PathDelegatingHandler();
	
	handler.addMapping("POST", "/upload", (ref HttpRequestContext ctx) {
		debug_("Receiving uploaded file...");
		debugF!"Headers: %s"(ctx.request.headers);
		
		ulong size = ctx.request.readBodyToFile("uploaded-file.txt", true);
		debugF!"Received %d bytes"(size);
		ctx.response.writeBodyString("Thank you!");
	});
	
	handler.addMapping("GET", "/source", (ref HttpRequestContext ctx) {
		debug_("Sending app source text.");
		const fileToDownload = buildPath("source", "app.d");
		auto sIn = FileInputStream(toStringz(fileToDownload));
		ctx.response.writeBody(sIn, getSize(fileToDownload), "text/plain");
	});

	return new HttpServer(handler, config);
}

private void logSep() {
	info("-----------------------------\n");
}
