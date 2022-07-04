import handy_httpd;
import handy_httpd.handlers.file_resolving_handler;
import std.socket;
import std.stdio;

void main() {
	auto h = new FileResolvingHandler("content");
	auto cfg = ServerConfig.defaultValues();
	cfg.connectionQueueSize = 500;
	cfg.preBindCallbacks ~= (s) {
		s.setOption(SocketOptionLevel.SOCKET, SocketOption.REUSEADDR, 1);
		writeln("Set REUSEADDR to true.");
	};
	auto s = new HttpServer(h, cfg);
	s.start();
}
