# handy-httpd

An extremely lightweight HTTP server for the [D programming language](https://dlang.org/). Handy-httpd uses a simple worker pool to process incoming requests, in conjunction with a user-defined `HttpRequestHandler`. Consider the following example:

```d
import handy_httpd;

void main() {
	auto s = new HttpServer(new FileResolvingHandler("static"));
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
- Connection queue size.
- Receive buffer size.
- Whether to show verbose logging output.
- Number of worker threads to use for request processing.


## Requests
Each HTTP request is parsed into the following struct for use with any `HttpRequestHandler`:
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

## Path-Delegating Handler
In many cases, you'll want a dedicated handler for specific URL paths on your server. You can achieve this with the `PathDelegatingHandler`.

```d
import handy_httpd.server;
import handy_httpd.responses;
import handy_httpd.handlers.path_delegating_handler;
import handy_httpd.handlers.file_resolving_handler;

auto handler = new PathDelegatingHandler()
	.addPath("/home", simpleHandler(request => okResponse()))
	.addPath("/users", simpleHandler(request => okResponse()))
	.addPath("/users/{id}", simpleHandler(request => okResponse()))
	.addPath("/files/**", new FileResolvingHandler("static-files"));

HttpServer server = new HttpServer(handler);
```

The `PathDelegatingHandler` allows you to register an `HttpRequestHandler` for specific path patterns. These patterns allow for some basic Ant-style path matching:

`**` will match any substring in a path, including multiple segments.
```
/users/**
  WILL match: /users
  WILL match: /users/123
  WILL match: /users/abc/123
  WILL NOT match: /user
```

`*` will match a single segment in a path.
```
/users/*
  WILL match: /users/123
  WILL match: /users/a
  WILL NOT match: /users/a/b
```

`?` will match a single character in a path.
```
/users/?
  WILL match: /users/a
  WILL match: /users/1
  WILL NOT match: /users/123
  WILL NOT match: /users
```
