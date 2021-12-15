import std.stdio;
import handy_httpd;

void main() {
	new HttpServer(req => handle(req)).start();
}

HttpResponse handle(HttpRequest request) {
	writeln(request);
	return HttpResponse(200, "OK");
}
