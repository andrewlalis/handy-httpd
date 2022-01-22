import handy_httpd;
import handy_httpd.handlers.file_resolving_handler;

void main() {
	new HttpServer(new FileResolvingHandler("content")).start();
}
