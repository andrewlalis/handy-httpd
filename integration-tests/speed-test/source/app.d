import slf4d;
import slf4d.provider;
import slf4d.writer;
import slf4d.default_provider;
import handy_httpd;

import std.algorithm;
import core.cpuid;

import requester;
import test;

int main() {
	auto prov = new DefaultProvider(true, Levels.INFO);
	prov.getLoggerFactory().setModuleLevelPrefix("handy_httpd", Levels.WARN);
	prov.getLoggerFactory().setModuleLevelPrefix("requester-", Levels.INFO);
	configureLoggingProvider(prov);

	const cpuThreads = threadsPerCPU();

	return runTests(
		// () => new SpeedTest("Single-Thread BlockingWorkerPool", getBlockingServer(), 4, LimitType.RequestCount, 10_000),
		() => new SpeedTest(
			"Single-Thread DistributingWorkerPool",
			getTestingServer(1),
			1,
			LimitType.Time, 10_000
		),
		() => new SpeedTest(
			"Multi-Thread DistributingWorkerPool",
			getTestingServer(max(1, cpuThreads)),
			max(1, cpuThreads / 2),
			LimitType.Time, 10_000
		)
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
	return new HttpServer(toHandler(&handlerFunction), new BlockingWorkerPool(1024), ServerConfig.init);
}

HttpServer getTestingServer(uint workerPoolSize) {
	ServerConfig config;
	config.workerPoolSize = workerPoolSize;
	return new HttpServer(&handlerFunction, config);
}

void handlerFunction(ref HttpRequestContext ctx) {
	ctx.response.writeBodyString("Testing server");
}

class FilesOnlyLoggingProvider : LoggingProvider {
	private DefaultLoggerFactory loggerFactory;

	public this() {
		auto handler = new SerializingLogHandler(
			new DefaultStringLogSerializer(false),
			new RotatingFileLogWriter("logs")
		);
		this.loggerFactory = new DefaultLoggerFactory(handler, Levels.INFO);
	}

	public DefaultLoggerFactory getLoggerFactory() {
		return this.loggerFactory;
	}
}
