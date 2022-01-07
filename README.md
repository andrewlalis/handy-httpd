# handy-httpd

An extremely lightweight HTTP server for the [D programming language](https://dlang.org/). Handy-httpd uses a simple worker pool to process incoming requests, in conjunction with a user-defined `HttpRequestHandler`. Consider the following example:

```d
import handy_httpd;

void main() {
	auto s = new HttpServer(new FileResolvingHandler());
	s.start();
}
```
> We create a new `HttpServer` that is using a `FileResolvingHandler` (tries to serve static files according to URL path), and start it. It's that simple.

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

Besides these barebones showcases, handy-httpd also gives you the ability to configure almost everything about how the server works, including the following properties:

- Hostname and port
- Receive buffer size.
- Whether to show verbose logging output.
- Number of worker threads to use for request processing.


## Requests
Each HTTP request parsed into the following struct for use with any `HttpRequestHandler`:
```d
struct HttpRequest {
    public const string method;
    public const string url;
    public const int ver;
    public const string[string] headers;
    public const string[string] params;
}
```

## Responses
The following struct is used to send responses from any `HttpRequestHandler`:
```d
struct HttpResponse {
    ushort status;
    string statusText;
    string[string] headers;
    ubyte[] messageBody;
```
