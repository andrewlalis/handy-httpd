import std.stdio;
import handy_httpd;
import std.stdio;
import std.socket;

void main() {
	auto cfg = ServerConfig.defaultValues();
	cfg.receiveBufferSize = 64_000;
	auto s = new HttpServer(simpleHandler(&handle), cfg);
	s.start();
}

void handle(ref HttpRequest req, ref HttpResponse resp) {
	writeln(req.bodyAsJson.toString);
	okResponse(resp, req.bodyAsJson.toString, "application/json");
}
