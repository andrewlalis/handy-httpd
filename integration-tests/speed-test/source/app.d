import slf4d;
import slf4d.default_provider;
import handy_httpd;

import std.datetime;
import core.cpuid;
import core.thread;

import requester;

int main() {
	auto prov = new shared DefaultProvider(false, Levels.INFO);
	prov.getLoggerFactory().setModuleLevelPrefix("handy_httpd", Levels.WARN);
	prov.getLoggerFactory().setModuleLevelPrefix("handy_httpd.components.request_queue", Levels.INFO);
	prov.getLoggerFactory().setModuleLevelPrefix("handy_httpd.components.worker_pool", Levels.INFO);
	prov.getLoggerFactory().setModuleLevelPrefix("handy_httpd.server", Levels.DEBUG);
	prov.getLoggerFactory().setModuleLevelPrefix("requester-", Levels.INFO);
	configureLoggingProvider(prov);

	HttpServer server = getTestingServer();
	Thread serverThread = new Thread(&server.start);
	serverThread.start();
	while (!server.isReady()) {
		Thread.sleep(msecs(1));
	}

	RequesterThread[] requesters;
	for (int i = 0; i < 4; i++) {
		requesters ~= new RequesterThread(i);
	}

	foreach (r; requesters) {
		r.start();
	}
	info("Started requesters.");

	Thread.sleep(seconds(3));
	info("Shutting down requesters.");
	foreach (r; requesters) {
		r.shutdown();
	}
	foreach (r; requesters) {
		r.join();
	}
	info("Shutdown requesters.");
	info("Shutting down server.");
	server.stop();
	info("Joining the server thread...");
	serverThread.join();
	info("Server stopped.");

	ulong totalRequests = 0;
	ulong successfulRequests = 0;
	foreach (r; requesters) {
		totalRequests += r.requestCount;
		successfulRequests += r.successCount;
	}
	double successRate = cast(double) totalRequests / successfulRequests;
	double requestsPerSecond = cast(double) successfulRequests / 3;
	infoF!"%d requests, %d successful, success rate %.3f, %.3f avg requests per second"(
		totalRequests,
		successfulRequests,
		successRate,
		requestsPerSecond
	);
	
	if (successRate < 0.95) {
		errorF!"Success rate of %.3f is less than 0.95."(successRate);
		return 1;
	}
	return 0;
}

HttpServer getTestingServer() {
	ServerConfig config = ServerConfig.defaultValues();
	config.workerPoolSize = 4;
	infoF!"Starting testing server with %d workers."(config.workerPoolSize);
	config.port = 8080;

	return new HttpServer((ref ctx) {
		ctx.response.writeBodyString("Testing server");
	}, config);
}
