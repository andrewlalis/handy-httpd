import std.stdio;
import handy_httpd;
import std.file;

void main() {
	new HttpServer((request) {
		if (request.url == "/" || request.url == "/index" || request.url == "/index.html") {
			return fileResponse("index.html", "text/html");
		} else {
			return HttpResponse(404, "Not Found");
		}
	}).start();
}
