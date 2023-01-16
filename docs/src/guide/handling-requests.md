# Handling Requests

As you've seen in the [introduction](./README.md), you can create a new server with a function that takes in an [HttpRequestContext](ddoc-handy_httpd.components.handler.HttpRequestContext). This function serves as a **handler**, that _handles_ incoming requests. In fact, that function is just a shorthand way of making an instance of the [HttpRequestHandler](ddoc-handy_httpd.components.handler.HttpRequestHandler) interface.

The HttpRequestHandler interface defines a single method: `void handle(ref HttpRequestContext ctx)` that takes a request context and performs everything that's needed to respond to that request.

Usually, to correctly respond to a request, you need to:
1. Read information from the HTTP request.
2. Do some logic based on that information.
3. Set the response status and headers.
4. Send the response body content (if there's any to send).

## The Request Context

The HttpRequestContext that's provided to the handler contains all the information needed to respond to the request. Information about the request itself is available via `ctx.request`, which is an [HttpRequest](ddoc-handy_httpd.components.request.HttpRequest) struct. We'll use some of the common properties of the request struct in this example, but please read the documentation for the full description of all available properties:

```d
import std.stdio;
import std.conv : to;
class MyHandler : HttpRequestHandler {
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
}
```