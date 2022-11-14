import handy_httpd;
import handy_httpd.handlers.file_resolving_handler;
import std.socket;
import std.stdio;

void main() {
	auto h = new FileResolvingHandler("content");
	auto cfg = ServerConfig.defaultValues();
	cfg.connectionQueueSize = 500;
	cfg.reuseAddress = true;
	auto s = new HttpServer(h, cfg);
	s.start();
}
