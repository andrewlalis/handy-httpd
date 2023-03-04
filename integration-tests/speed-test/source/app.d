import slf4d;
import slf4d.default_provider;
import handy_httpd;

import core.cpuid;
import core.thread;

int main() {
	auto prov = new shared DefaultProvider(false);
	prov.getLoggerFactory().setModuleLevel("handy_httpd", Levels.WARN);
	configureLoggingProvider(prov);
	auto log = getLogger();

	HttpServer server = getTestingServer();
	Thread serverThread = new Thread(&server.start);
	serverThread.start();

	RequesterThread[] requesters;
	for (int i = 0; i < threadsPerCPU / 2; i++) {
		requesters ~= new RequesterThread();
	}

	foreach (r; requesters) {
		r.start();
	}
	log.info("Started requesters.");

	Thread.sleep(seconds(10));
	log.info("Shutting down requesters.");
	foreach (r; requesters) r.shutdown();
	foreach (r; requesters) r.join();
	log.info("Shutdown requesters.");
	log.info("Shutting down server.");
	server.stop();
	serverThread.join();
	log.info("Server stopped.");

	ulong totalRequests = 0;
	ulong successfulRequests = 0;
	foreach (r; requesters) {
		totalRequests += r.requestCount;
		successfulRequests += r.successCount;
	}
	double successRate = cast(double) totalRequests / successfulRequests;
	double requestsPerSecond = cast(double) successfulRequests / 3;
	log.infoF!"%d requests, %d successful, success rate %.3f, %.3f avg requests per second"(
		totalRequests,
		successfulRequests,
		successRate,
		requestsPerSecond
	);
	
	if (successRate < 0.95) {
		log.errorF!"Success rate of %.3f is less than 0.95."(successRate);
		return 1;
	}
	return 0;
}

HttpServer getTestingServer() {
	auto log = getLogger();
	ServerConfig config = ServerConfig.defaultValues();
	config.workerPoolSize = threadsPerCPU / 2;
	log.infoF!"Starting testing server with %d workers."(config.workerPoolSize);
	config.port = 8080;

	return new HttpServer((ref ctx) {
		ctx.response.writeBodyString("Testing server");
	}, config);
}

class RequesterThread : Thread {
	import core.atomic;

	ulong requestCount;
	ulong successCount;
	bool running;

	this() {
		super(&this.run);
	}

	private void run() {
		import requests;

		atomicStore(running, true);
		while (atomicLoad(running)) {
			try {
				string content = cast(string) getContent("http://localhost:8080/").data;
				if (content == "Testing server") {
					successCount++;
				}
			} catch (Exception e) {
				// getLogger().error(e);
			} finally {
				requestCount++;
			}
		}
	}

	public void shutdown() {
		atomicStore(running, false);
	}
}
