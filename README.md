# handy-httpd

An extremely lightweight HTTP server for the [D programming language](https://dlang.org/). Handy-httpd uses a simple worker pool to process incoming requests, in conjunction with a user-defined `HttpRequestHandler`. Consider the following example in which we serve files from the `./static/` directory:

```d
import handy_httpd;
import handy_httpd.handlers.file_resolving_handler;

void main() {
	auto s = new HttpServer(new FileResolvingHandler("static"));
	s.start();
}
```

It's also quite simple to define your own custom request handler. Here's an example of a custom request handler that only responds to the `/hello` endpoint:

```d
import handy_httpd;

void main() {
	auto s = new HttpServer(simpleHandler((request) {
		if (request.url == "/hello") {
			return okResponse()
				.setBody("Hello world!");
		} else {
			return notFound();
		}
	}));
	s.start();
}
```
> Note: the `HttpRequestHandler simpleHandler(HttpResponse function(HttpRequest) fn)` function allows you to pass a function as a request handler. Internally, it's using an anonymous class.

For more information, please check out the [wiki on GitHub](https://github.com/andrewlalis/handy-httpd/wiki).
