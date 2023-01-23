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

Information about the request itself is available via the request context's `request` attribute, which is an [HttpRequest](ddoc-handy_httpd.components.request.HttpRequest) struct containing the basic information about the parsed request, as well as methods for consuming the rest of the request body (if applicable).

#### Basic Properties

Every HTTP request has a string `url` and `method`; for example, `GET http://example.com/index.html` or `POST http://example.com/data`. The request also contains an integer `ver` version identifier, which generally should always be set to `1` since Handy-Httpd doesn't support HTTP 2 or higher.

```d
void handle(ref HttpRequestContext ctx) {
    if (ctx.request.url == "/users" && ctx.request.method == "GET") {
        // Retrieve list of users.
    }
}
```
A request's `method` will **always** be capitalized. Also, the `url` is relative to the base hostname of the server, so if you do `GET http://localhost:8080/data`, the request's `url` will be `/data`.

#### Headers and Parameters

The request's headers are available via the `headers` associative array, where each header name is mapped to a single string value. There are no guarantees about which headers may be present, nor their type. It's generally up to the handler to figure out how to deal with them.

Similarly, the request's `params` associative array contains the named list of parameters that were parsed from the URL. For example, in `http://example.com/?x=5`, Handy-Httpd would provide a request whose params are `[x = "5"]`. Like the headers, no guarantee is made about what params are present, or what type they are. However, you can use the `getParamAs` function as a safe way to get a parameter as a specified type, or fallback to a default.

```d
void handle(ref HttpRequestContext ctx) {
    int page = ctx.request.getParamAs!int("page", 1);
    // Do other stuff below...
}
```

#### Path Parameters

If a request is handled by a [PathDelegatingHandler](ddoc-handy_httpd.handlers.path_delegating_handler.PathDelegatingHandler), then its `pathParams` associative array will be populated with any path parameters that were parsed from the URL.

The easiest way to understand this behavior is through an example. Suppose we define our top-level PathDelegatingHandler with the following mapping, so that a `userSettingsHandler` will handle requests to that endpoint:

```d
auto handler = new PathDelegatingHandler();
handler.addMapping("/users/{userId}/settings/{setting}", userSettingsHandler);
```

Then in our `userSettingsHandler` we can retrieve the path parameters like so:

```d
void handle(ref HttpRequestContext ctx) {
    string userId = ctx.request.pathParams["userId"];
    // Or more safely:
    int userId2 = ctx.request.getPathParamAs!int("userId", -1);
    // Do stuff for this user...
}
```

#### Body Content

Some requests that your server receives may include a body, which is any content that comes after the URL and headers of the request. The request offers a few low-level attributes to enable you to manually process the request body if you'd like, or you can use one of the available helper methods.

To see if a request contains a body that should be read, you can call `request.hasBody()`, which returns **`true`** if we detect that there's content to be read.
> A request is determined to have a body if the number of bytes received exceeds the `receiveBufferOffset`, or if a `"Content-Length"` header with a positive integer value is present. See [Low-Level Reading](#low-level-reading) for more info.

To read the request body, you can call the `request.readBody` method, passing an [Output range](https://dlang.org/phobos/std_range_primitives.html#isOutputRange) that accepts chunks of `ubyte[]` that are produced as the body is read. Let's see how that could work with a simple example that prints each chunk to stdout as it's read:

```d
struct StdoutPrinter {
    void put(ubyte[] data) {
        import std.stdio : writeln;
        string s = cast(string) data;
        writeln(s);
    }
}

StdoutPrinter p;
request.readBody(p);
```

To make your life easier, we've included a number of pre-defined helper methods that read the request body to common output formats.

- `readBodyAsString()` will read the entire request body into a `string`.
- `readBodyAsJson()` will read the request body into a [JSONValue](https://dlang.org/phobos/std_json.html#.JSONValue), or throw a [JSONException](https://dlang.org/phobos/std_json.html#JSONException) or [ConvException](https://dlang.org/phobos/std_json.html#ConvException) if the body's content is not valid JSON, or if a number in the input can't be represented with a D type.
- `readBodyToFile(string filename)` will read the request body and write it to the given file. If a file already exists at `filename`, it will be overwritten.

##### Low-Level Reading

For low-level access, you can read from the request's `clientSocket`. The request provides a `ubyte[]* receiveBuffer`, which is a pointer to the receive buffer belonging to the worker thread that's processing the request. It's highly recommended to use this to receive additional data, instead of creating a separate buffer. When a request is first parsed, we read as much data as can fit into the receive buffer (its size is configured via the [receiveBufferSize](./configuration.md#receivebuffersize) property). This means that part (or all) of the request body might have been read in the first attempt to receive data. In order to retrieve this data, the request contains the `size_t receiveBufferOffset` and `size_t receivedByteCount` attributes which specify the offset in the buffer where the body would start (1 past the end of the headers), and the number of bytes that were received in total, respectively.

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
    ctx.writeBody("{\"id\": 1}", "application/json");
}
```

#### Status and Headers

The first thing you should do when responding to a request is to send a status, and headers. The response's `ushort status` can be set to one of the [valid HTTP response statuses](https://developer.mozilla.org/en-US/docs/Web/HTTP/Status), depending on the situation. You may also want to set the request's `string statusText` to something like `"Not Found"` if you return a 404 status, for example.

You can add headers via `request.addHeader(string name, string value)`.

> Note that setting the status, statusText, and headers is only possible before they've been flushed, i.e. before any body content is sent.

#### Writing the Response Body

After setting a status and headers, you can write the response body to the response's `clientSocket`. This can be done manually by invoking `response.clientSocket.send`, or with one of the helper methods provided by the response.

- `writeBody(inputRange, ulong size, string contentType)` will write the response body using data taken from an input range that supplies `ubyte[]` chunks. The size and content type are used to set headers before the actual data is sent.
- `writeBody(ubyte[] body, string contentType)` will write the given content to the response body.
- `writeBody(string text)` will write plain text to the response body.

### Socket and Server

While you'll normally only use the request and response components of the request context, it also contains a reference to the underlying [Socket](https://dlang.org/phobos/std_socket.html#.Socket) that's used for communication, as well as a reference to the [HttpServer](ddoc-handy_httpd.server.HttpServer) that's handling the request. Feel free to use these components if you need, but if you do, be aware of some implementation details of Handy-httpd:

- The socket is a classic TCP socket, and when passed to a handler via a context, the request has already been read from the socket's input stream.
- When a response's status and headers are flushed to the socket's output stream, an internal `flushed` flag is set to **true**. If the response hasn't been flushed by the time that a handler has finished with the context, it'll be flushed by the worker thread handling the request. Therefore, if you plan to write content to the socket, be sure to flush the headers beforehand, to avoid having them dumped at the end of the socket's output. You may use [HttpResponse.flushHeaders](ddoc-handy_httpd.components.response.HttpResponse.flushHeaders).
- The request context passed to a server is local to the current worker thread. However, the server reference in that context refers to the single server to which all worker threads belong. Therefore, be aware of the potential concurrency issues if you decide to operate on the shared server instance.
