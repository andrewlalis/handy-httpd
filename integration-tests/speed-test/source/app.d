import slf4d;
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

	SpeedTest singleThreadTest = new SpeedTest(
		getTestingServer(1),
		1,
		LimitType.Time,
		10_000
	);
	if (!singleThreadTest.run()) return 1;

	SpeedTest balancedThreadTest = new SpeedTest(
		getTestingServer(threadsPerCPU / 2),
		threadsPerCPU / 2,
		LimitType.Time,
		10_000
	);
	if (!balancedThreadTest.run()) return 1;

	return 0;
}

HttpServer getTestingServer(uint workerPoolSize) {
	ServerConfig config = ServerConfig.defaultValues();
	config.workerPoolSize = workerPoolSize;
	config.enableWebSockets = false;
	config.connectionQueueSize = 1000;
	config.receiveBufferSize = 1024;
	infoF!"Starting testing server with %d workers."(config.workerPoolSize);
	config.port = 8080;

	return new HttpServer((ref ctx) {
		ctx.response.writeBodyString("Testing server");
	}, config);
}
