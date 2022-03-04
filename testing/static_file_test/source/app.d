import handy_httpd;
import handy_httpd.handlers.file_resolving_handler;

void main() {
	auto h = new FileResolvingHandler("content");
	auto s = new HttpServer(h, "127.0.0.1", 8080, 8192, 500, false, 100);
	s.start();
}
