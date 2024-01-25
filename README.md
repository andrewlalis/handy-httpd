# handy-httpd

An extremely lightweight HTTP server for the [D programming language](https://dlang.org/).

## Features
- HTTP/1.1
- [Web Sockets](https://andrewlalis.github.io/handy-httpd/guide/handlers/websocket-handler.html)
- [Simple configuration](https://andrewlalis.github.io/handy-httpd/guide/configuration.html)
- High performance with interchangeable request processors
- Beginner friendly
- Extensible with custom handlers, exception handlers, and filters
- [Well-documented](https://andrewlalis.github.io/handy-httpd/)
- [Prioritises testability](https://andrewlalis.github.io/handy-httpd/guide/testing.html)
- Ships with some handy pre-made request handlers:
	- Serve static files with the [FileResolvingHandler](https://andrewlalis.github.io/handy-httpd/guide/handlers/file-resolving-handler.html)
	- Apply filters before and after handling requests with the [FilteredHandler](https://andrewlalis.github.io/handy-httpd/guide/handlers/filtered-handler.html)
	- Handle complex URL paths, including path parameters and wildcards, with the [PathHandler](https://andrewlalis.github.io/handy-httpd/guide/handlers/path-handler.html)

## Links
- [Documentation](https://andrewlalis.github.io/handy-httpd/)
- [Examples](https://github.com/andrewlalis/handy-httpd/tree/main/examples)
- [Dub Package Page](https://code.dlang.org/packages/handy-httpd)
- [Bugs/Feature Requests](https://github.com/andrewlalis/handy-httpd/issues)
- [User Feedback Form](https://docs.google.com/forms/d/e/1FAIpQLSdazfaKLghGk1XpefOyDdHFfSZLaHQlCaeI9KAsaIMR5iNX6A/viewform?usp=sf_link)

## Simple Example
```d
import handy_httpd;

void main() {
	new HttpServer((ref ctx) {
		ctx.response.writeBodyString("Hello world!");
	}).start();
}
```
