import handy_httpd;
import handy_httpd.handlers.file_resolving_handler;

void main() {
	auto s = new HttpServer(new FileResolvingHandler("content"));
	s.setVerbose(false);
	s.start();
}
