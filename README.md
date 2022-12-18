# handy-httpd

An extremely lightweight HTTP server for the [D programming language](https://dlang.org/).

##### Table of Contents
1. [Start Your Server](#start-your-server)
2. [Request Handlers](#request-handlers)
3. [Configuration](#configuration)
4. [Architecture](#architecture)
5. [Developing](#developing)

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

## Request Handlers
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

### Deploying to Production
While it's not recommended to use Handy-httpd in production for critical infrastructure, you can still use it; maybe for smaller services or testing projects. In that case, it's recommended to run it behind nginx or some other reverse proxy server that handles raw request logging, SSL, and all the other aspects of a fully-featured web server.

## Architecture
It's been discussed briefly before, but in this section, we'll go into detail about how Handy-httpd is designed.

Handy-httpd is structured as a classic socket-based threaded server, where as the server accepts incoming connections, they are passed on to worker threads for processing.

The server is configured with exactly one `HttpRequestHandler`, and exactly one `ServerExceptionHandler`.
- If no request handler is provided, it will default to a _no-op_ handler that simply returns a "503 Service Unavailable" response.
- If no exception handler is provided, it will default to the `BasicServerExceptionHandler` that logs the exception's message, and returns a "500 Internal Server Error" response if any handler throws an exception.

If you'd like to have more than one way to handle requests or exceptions, you can accomplish that by composition. In the [Request Handlers section](#request-handlers), an example was given in which a `PathDelegatingHandler` was used to create a composite handler for files and API requests. Similarly with exception handling, you could define a custom exception handler that implements `ServerExceptionHandler`. Below is a simple example:

```d
class MyExceptionHandler : ServerExceptionHandler {
	void handle(ref HttpRequestContext ctx, Exception e) {
		if (auto nf = cast(NotFoundException) e) {
			ctx.response.notFound();
		} else if (auto ae = cast(AuthException) e) {
			ctx.response.status = 401;
			ctx.response.statusText = "Unauthorized";
			ctx.response.writeBody("You are not authorized.");
		} else {
			ctx.response.status = 500;
			ctx.response.writeBody("An error occurred.");
		}
	}
}
```
> Note: `NotFoundException` and `AuthException` are just hypothetical names for exception classes you might have.

### Filters
While it's not enforced at all in Handy-httpd, many web frameworks make use of some form of configurable _filter_, that is, middleware that operates on an HTTP request context before or after it's processed by a handler.

To that end, Handy-httpd does offer the `handy_httpd.handlers.filtered_handler` module, which defines the following components:

- `HttpRequestFilter` - An interface that defines a filter as a component that simply operates on a request context, and calls the next filter in the chain if successful.
- `FilterChain` - A singly-linked list of filters that can be called in a chain.
- `FilteredRequestHandler` - An implementation of `HttpRequestHandler` that applies a series of pre- and post-request filters to each handled request.

For example, one might want to check a request to ensure it's got an authentication token header before handing it off to any other handler. We can accomplish that like so:

```d
class AuthFilter : HttpRequestFilter {
	void apply(ref HttpRequestContext ctx, FilterChain filterChain) {
		if ("X-API-TOKEN" in ctx.request.headers) {
			string token = ctx.request.headers;
			if (isValid(token)) {
				filterChain.doFilter(ctx);
				return;
			}
		}
		// Otherwise, return a 401 unauthorized response.
		ctx.response.status = 401;
		ctx.response.writeBody("Invalid authentication.");
	}
}

auto apiHander = new ApiRequestHandler();
auto filteredHandler = new FilteredRequestHandler(
	apiHandler, // The handler to use.
	[new AuthFilter()] // Pre-request filters.
	// No post-request filters to add.
);
auto server = new HttpServer(filteredHandler);
server.start();
```

## Developing
When developing or making changes to Handy-httpd, you can test it simply by making a proof-of-concept server for the feature you're adding, and declaring its handy-httpd dependency path to point to your local instance of this project. For example, see `testing/static_file_test` for a server that will always use the local handy-httpd version as its dependency.
