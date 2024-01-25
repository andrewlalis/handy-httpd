import slf4d;
import slf4d.provider;
import slf4d.writer;
import slf4d.default_provider;
import handy_httpd;

import core.cpuid;

import requester;
import test;

int main() {
	auto prov = new shared DefaultProvider(true, Levels.INFO);
	prov.getLoggerFactory().setModuleLevelPrefix("handy_httpd", Levels.WARN);
	prov.getLoggerFactory().setModuleLevelPrefix("requester-", Levels.INFO);
	configureLoggingProvider(prov);

	const cpuThreads = threadsPerCPU();

	return runTests(
		// () => new SpeedTest("Single-Thread BlockingWorkerPool", getBlockingServer(), 4, LimitType.RequestCount, 10_000),
		() => new SpeedTest("Single-Thread DistributingWorkerPool", getTestingServer(1), 1, LimitType.Time, 10_000),
		() => new SpeedTest("Multi-Thread DistributingWorkerPool", getTestingServer(cpuThreads), cpuThreads / 2, LimitType.Time, 10_000)
	);
}

int runTests(SpeedTest delegate()[] tests...) {
	bool[] results = new bool[tests.length];
	foreach (i, test; tests) {
		results[i] = test().run();
	}
	foreach (result; results) {
		if (!result) return 1;
	}
	return 0;
}

HttpServer getBlockingServer() {
	import handy_httpd.components.worker_pool;
	ServerConfig config = ServerConfig.defaultValues();
	return new HttpServer(toHandler(&handlerFunction), new BlockingWorkerPool(1024), config);
}

HttpServer getTestingServer(uint workerPoolSize) {
	ServerConfig config = ServerConfig.defaultValues();
	config.workerPoolSize = workerPoolSize;
	return new HttpServer(&handlerFunction, config);
}

void handlerFunction(ref HttpRequestContext ctx) {
	ctx.response.writeBodyString("Testing server");
}

class FilesOnlyLoggingProvider : LoggingProvider {
	private shared DefaultLoggerFactory loggerFactory;

	public shared this() {
		auto handler = new shared SerializingLogHandler(
			new DefaultStringLogSerializer(false),
			new RotatingFileLogWriter("logs")
		);
		this.loggerFactory = new shared DefaultLoggerFactory(handler, Levels.INFO);
	}

	public shared shared(DefaultLoggerFactory) getLoggerFactory() {
		return this.loggerFactory;
	}
}
