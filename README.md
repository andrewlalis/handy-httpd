# handy-httpd

An extremely lightweight HTTP server for the [D programming language](https://dlang.org/).

## Start Your Server
In this example, we take advantage of the [Dub package manager](https://code.dlang.org/)'s single-file SDL syntax to declare HandyHttpd as a dependency. For this example, we'll call this `my_server.d`.
```d
#!/usr/bin/env dub
/+ dub.sdl:
	dependency "handy_httpd" version="~>3.4"
+/
import handy_httpd;

void main() {
	new HttpServer((ref ctx) {
		if (ctx.request.url == "/hello") {
			response.writeBody("Hello world!");
		} else {
			response.notFound();
		}
	}).start();
}
```
To start the server, just mark the script as executable, and run it:

```shell
chmod +x my_server.d
./my_server.d
```

And finally, if you navigate to http://localhost:8080/hello, you should see the `Hello world!` text appear.

## Handlers
handy-httpd operates under the concept of a "handler"; a single component that's responsible for handling an HTTP request and writing a response. Every server is configured with one, and only one handler. In the above example, we defined the handler using D's function syntax. You can also make your own handler class which implements the `handy_httpd.components.handler.HttpRequestHandler` interface.

For your convenience, several pre-made handlers have been supplied with handy-httpd, and can be imported with `import handy_httpd.handlers;`. These are:

- `FileResolvingHandler` - A handler that resolves GET requests for files within a configured base directory, and serves the files to clients.
- `PathDelegatingHandler` - A handler that delegates actual handling to one of many possible handlers that have each been registered with an Ant-style path pattern, like `/users/{id}` or `/systems/beta/**`.
- `FilteredRequestHandler` - A handler that applies a series of "filters" to a request before and/or after handling the request.

While the handy-httpd server only offers the possibility of configuring a single request handler, complex applications can be built by composing handlers, like the pre-made ones listed above do.

For example, suppose we want to run a server that serves files from one path (say, `/files/**`), and programmatically handles requests using our own handlers from another path (`/app/**`). We can construct a handler for this like so:
```d
auto fileHandler = new FileResolvingHandler("assets");
auto appHandler = new PathDelegatingHandler()
	.addPath("/app/users", (ref ctx) {
		ctx.response.writeBody("John Smith");
	})
	.addPath("/app/data", (ref ctx) {
		ctx.response.writeBody("data");
	});
auto handler = new PathDelegatingHandler()
	.addPath("/files/**", fileHandler)
	.addPath("/app/**", appHandler);
```

## Configuration
The handy-httpd server is configured using a simple struct that's defined in `handy_httpd.components.config`. Unless you provide a `ServerConfig` when creating your server, it defaults to the following settings (as taken from the source code):

```d
static ServerConfig defaultValues() {
	ServerConfig cfg;
	cfg.hostname = "127.0.0.1";
	cfg.port = 8080;
	cfg.receiveBufferSize = 8192;
	cfg.connectionQueueSize = 100;
	cfg.reuseAddress = true;
	cfg.verbose = false;
	cfg.workerPoolSize = 25;
	return cfg;
}
```
