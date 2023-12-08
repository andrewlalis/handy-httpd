# Handling Requests

As you've seen in the [introduction](./README.md), you can create a new server with a function that takes in an [HttpRequestContext](ddoc-handy_httpd.components.handler.HttpRequestContext). This function serves as a **handler**, that _handles_ incoming requests. In fact, that function is just a shorthand way of making an instance of the [HttpRequestHandler](ddoc-handy_httpd.components.handler.HttpRequestHandler) interface.

The HttpRequestHandler interface defines a single method: [handle](ddoc-handy_httpd.components.handler.HttpRequestHandler.handle), that takes a request context and performs everything that's needed to respond to that request.

Usually, to correctly respond to a request, you need to:
1. Read information from the HTTP request.
2. Do some logic based on that information.
3. Set the response status and headers.
4. Send the response body content (if there's any to send).

## The Request Context

The HttpRequestContext that's provided to the handler contains all the information needed to respond to the request. This includes:

- The [HttpRequest](ddoc-handy_httpd.components.request.HttpRequest) that was received.
- The [HttpResponse](ddoc-handy_httpd.components.response.HttpResponse) that will be sent.
- The [HttpServer](ddoc-handy_httpd.server.Server) that received the request.
- The [ServerWorkerThread](ddoc-handy_httpd.components.worker.ServerWorkerThread) that's processing the request.

### Request

Information about the request itself is available via the request context's `request` attribute, which is an [HttpRequest](ddoc-handy_httpd.components.request.HttpRequest) struct containing the basic information about the parsed request, as well as methods for consuming the rest of the request body (if applicable).

#### Basic Properties

Every HTTP request has a string `url` and `method`; for example, `GET http://example.com/index.html` or `POST http://example.com/data`. The request also contains an integer `ver` version identifier, which generally should always be set to `1` since Handy-Httpd doesn't support HTTP 2 or higher.

```d
void handle(ref HttpRequestContext ctx) {
    if (ctx.request.url == "/users" && ctx.request.method == Method.GET) {
        // Retrieve list of users.
    }
}
```
The `url` is relative to the base hostname of the server, so if you do `GET http://localhost:8080/data`, the request's `url` will be `/data`.

Each request also contains a `remoteAddress`, which contains the remote socket address of the client that issued the request. Keep in mind that this might be null, and probably will be for most unit tests. See [std.socket : Address](https://dlang.org/phobos/std_socket.html#.Address) in Phobos for more information on how to work with addresses.

#### Headers and Parameters

The request's headers are available via the `headers` associative array, where each header name is mapped to a single string value. There are no guarantees about which headers may be present, nor their type. It's generally up to the handler to figure out how to deal with them.

Similarly, the request's `params` associative array contains the named list of parameters that were parsed from the URL. For example, in `http://example.com/?x=5`, Handy-Httpd would provide a request whose params are `[x = "5"]`. Like the headers, no guarantee is made about what params are present, or what type they are. However, you can use the [getParamAs](ddoc-handy_httpd.components.request.HttpRequest.getParamAs) function as a safe way to get a parameter as a specified type, or fallback to a default.

```d
void handle(ref HttpRequestContext ctx) {
    int page = ctx.request.getParamAs!int("page", 1);
    // Do other stuff below...
}
```

#### Path Parameters

If a request is handled by a [PathHandler](ddoc-handy_httpd.handlers.path_handler.PathHandler), then its `pathParams` associative array will be populated with any path parameters that were parsed from the URL.

The easiest way to understand this behavior is through an example. Suppose we define our top-level PathHandler with the following mapping, so that a `userSettingsHandler` will handle requests to that endpoint:

```d
auto handler = new PathHandler();
handler.addMapping("/users/:userId:ulong/settings/:setting", userSettingsHandler);
```

Then in our `userSettingsHandler` we can retrieve the path parameters like so:

```d
void handle(ref HttpRequestContext ctx) {
    ulong userId2 = ctx.request.getPathParamAs!ulong("userId");
    string setting = ctx.request.pathParams["setting"];
    // Do stuff for this user...
}
```

For more information about the PathHandler, please see the [dedicated page on this topic](./handlers/path-handler.md).

#### Body Content

Some requests that your server receives may include a body, which is any content that comes after the URL and headers of the request. The [HttpRequest](ddoc-handy_httpd.components.request.HttpRequest) offers the following methods for reading the body of the request:

| <div style="width: 150px;">Method</div> | Description |
|---     |---          |
| [readBody](ddoc-handy_httpd.components.request.HttpRequest.readBody) | Reads the request body, and writes it to a given output stream. Unless you explicitly enable *infinite reading*, it will respect the request's `Content-Length` header, and if no such header is present, nothing will be read. |
| [readBodyAsBytes](ddoc-handy_httpd.components.request.HttpRequest.readBodyAsBytes) | Reads the entire request body to a byte array. |
| [readBodyAsString](ddoc-handy_httpd.components.request.HttpRequest.readBodyAsString) | Reads the entire request body to a string. |
| [readBodyAsJson](ddoc-handy_httpd.components.request.HttpRequest.readBodyAsJson) | Reads the entire request body as a [JSONValue](https://dlang.org/phobos/std_json.html#.JSONValue). |
| [readBodyToFile](ddoc-handy_httpd.components.request.HttpRequest.readBodyToFile) | Reads the entire request body and writes it to a given file. |

> Note: While Handy-Httpd doesn't force you to limit the amount of data you read, please be careful when reading an entire request body at once, like with `readBodyAsString`. This will load the entire request body into memory, and **will** crash your program if the body is too large.

Sometimes, the body content of a request may be encoded if the `Transfer-Encoding=chunked` header is provided. In that case, Handy-Httpd will automatically wrap the underlying input stream with one that reads the chunked encoding and provides you with the raw data. In short, you Handy-Httpd will manage chunked encoded requests for you. However, it *will not* automatically apply chunked encoding to your server's responses.

### Response

Besides the request itself, the request context also contains the [HttpResponse](ddoc-handy_httpd.components.response.HttpResponse) to which your handler will write its response data. Usually, you'll follow the standard sequence of events mentioned above, and you'll:
1. Set the response status and headers.
2. Send the response body content (if necessary).

What this might look like in practice is shown in the example below:
```d
void handle(ref HttpRequestContext ctx) {
    // Do logic on request.
    ctx.response.status = HttpStatus.CREATED;
    ctx.response.addHeader("X-MY-TOKEN", "abc");
    // Calling `writeBodyString` will automatically flush the status and headers to the socket.
    ctx.response.writeBodyString("{\"id\": 1}", "application/json");
}
```

#### Status and Headers

The first thing you should do when responding to a request is to send a status, and headers. The response's `status` can be set according to a value from the [HttpStatus](ddoc-handy_httpd.components.response.HttpStatus) enum, which lists every valid HTTP status code and its associated textual representation.

You can add headers via [addHeader(string name, string value)](ddoc-handy_httpd.components.response.HttpResponse.addHeader).

> Note that setting the status and headers is only possible before they've been flushed, i.e. before any body content is sent.

#### Writing the Response Body

After setting a status and headers, you can write the response body. This can be done with one of the methods provided by the response:

| <div style="width: 150px;">Method</div> | Description |
|---     |---          |
| [writeBody](ddoc-handy_httpd.components.response.HttpResponse.writeBodyRange) | Writes the response body using data taken from an input stream of bytes. The size and content type must be explicitly specified before anything is written. |
| [writeBodyBytes](ddoc-handy_httpd.components.response.HttpResponse.writeBodyBytes) | Writes the given bytes to the response body. You can optionally specify a content type, or it'll default to `application/octet-stream`. |
| [writeBodyString](ddoc-handy_httpd.components.response.HttpResponse.writeBodyString) | Writes the given text to the response body. You can optionally specify a content type, or it'll default to `text/plain; charset=utf-8`. |

## IO

For IO operations while handling requests, Handy-Httpd uses the [streams](https://github.com/andrewlalis/streams) library. It offers a simple interface for input and output stream primitives, and is generally a bit more extensible than the ranges that are present in the Phobos standard library.

**Input streams** read from some underlying resource. In the case of HTTP, that mostly means that when we receive a request, we construct a `SocketInputStream` around the TCP socket we're using for the connection.

Conversely, **output streams** write to some underlying resource, and again, since we're talking HTTP, that means we use a `SocketOutputStream` to write bytes to the TCP socket.

The `read...` and `write...` methods of the [HttpRequest](ddoc-handy_httpd.components.request.HttpRequest) and the [HttpResponse](ddoc-handy_httpd.components.response.HttpResponse), respectively, are just wrappers around the underlying `readFromStream` and `writeToStream` methods of the input and output streams.

> For a more in-depth explanation, please read the documentation available at the streams library's source.
