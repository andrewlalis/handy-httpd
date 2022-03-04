# handy-httpd

An extremely lightweight HTTP server for the [D programming language](https://dlang.org/).

For a complete overview, please visit [the wiki](https://github.com/andrewlalis/handy-httpd/wiki).

Here's an example of serving static files from a directory:
```d
import handy_httpd;
import handy_httpd.handlers.file_resolving_handler;

void main() {
	new HttpServer(new FileResolvingHandler("static")).start();
}
```

It's also quite simple to define your own custom request handler. Here's an example of a custom request handler that only responds to the `/hello` endpoint:
```d
import handy_httpd;
import handy_httpd.responses;

void main() {
	auto s = new HttpServer(simpleHandler((ref request, ref response) {
		if (request.url == "/hello") {
			response.writeBody("Hello world!");
		} else {
			response.notFound();
		}
	}));
	s.start();
}
```
