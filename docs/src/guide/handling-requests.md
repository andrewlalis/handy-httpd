# Handling Requests

As you've seen in the [introduction](./README.md), you can create a new server with a function that takes in an [HttpRequestContext](ddoc-handy_httpd.components.handler.HttpRequestContext). This function serves as a **handler**, that _handles_ incoming requests. In fact, that function is just a shorthand way of making an instance of the [HttpRequestHandler](ddoc-handy_httpd.components.handler.HttpRequestHandler) interface.

The HttpRequestHandler interface defines a single method: `void handle(ref HttpRequestContext ctx)` that takes a request context and performs everything that's needed to respond to that request.

Usually, to correctly respond to a request, you need to:
1. Read information from the HTTP request.
2. Do some logic based on that information.
3. Set the response status and headers.
4. Send the response body content (if there's any to send).

## The Request Context

The HttpRequestContext that's provided to the handler contains all the information needed to respond to the request.

### Request

Information about the request itself is available via `ctx.request`, which is an [HttpRequest](ddoc-handy_httpd.components.request.HttpRequest) struct. We'll use some of the common properties of the request struct in this example, but please read the documentation for the full description of all available properties:

```d
void handle(ref HttpRequestContext ctx) {
    if (ctx.request.url == "/test") { // Check the request's URL.
        // Get a value from the request's headers.
        writefln!"User agent: %s"(ctx.request.headers["User-Agent"]);
        // Get a URL parameter as an integer.
        int page = ctx.request.getParamAs!int("page", 0);
        int size = ctx.request.getParamAs!int("size", 50);
        // Get the request's body content:
        writefln!"Request body:\n%s"(ctx.request.bodyContent);
        ctx.response.okResponse();
    }
}
```

### Response

Besides the request itself, the request context also contains the [HttpResponse](ddoc-handy_httpd.components.response.HttpResponse) to which your handler will write its response data. Usually, you'll follow the standard sequence of events mentioned above, and you'll:
1. Set the response status and headers.
2. Send the response body content (if necessary).

What this might look like in practice is shown in the example below:
```d
void handle(ref HttpRequestContext ctx) {
    // Do logic on request.
    ctx.response.status = 201;
    ctx.response.statusText = "Created";
    ctx.response.addHeader("X-MY-TOKEN", "abc");
    // Calling `writeBody` will automatically flush the status and headers to the socket.
    ctx.writeBody("{\"id\": 1}");
}
```

### Socket and Server

While you'll normally only use the request and response components of the request context, it also contains a reference to the underlying [Socket](https://dlang.org/phobos/std_socket.html#.Socket) that's used for communication, as well as a reference to the [HttpServer](ddoc-handy_httpd.server.HttpServer) that's handling the request. Feel free to use these components if you need, but if you do, be aware of some implementation details of Handy-httpd:

- The socket is a classic TCP socket, and when passed to a handler via a context, the request has already been read from the socket's input stream.
- When a response's status and headers are flushed to the socket's output stream, an internal `flushed` flag is set to **true**. If the response hasn't been flushed by the time that a handler has finished with the context, it'll be flushed by the worker thread handling the request. Therefore, if you plan to write content to the socket, be sure to flush the headers beforehand, to avoid having them dumped at the end of the socket's output. You may use [HttpResponse.flushHeaders](ddoc-handy_httpd.components.response.HttpResponse.flushHeaders).
- The request context passed to a server is local to the current worker thread. However, the server reference in that context refers to the single server to which all worker threads belong. Therefore, be aware of the potential concurrency issues if you decide to operate on the shared server instance.
