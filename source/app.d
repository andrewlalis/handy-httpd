import handy_httpd;

void main() {
	auto s = new HttpServer(new FileResolvingHandler());
	s.start();
}
