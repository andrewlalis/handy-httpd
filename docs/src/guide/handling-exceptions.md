# Handling Exceptions

As a matter of principle, you should try to handle all exceptions as close to their source as possible. However, sometimes that's not practical, or just too verbose. In that case, Handy-Httpd provides a safeguard for you: the [ServerExceptionHandler](ddoc-handy_httpd.components.handler.ServerExceptionHandler). Each HttpServer has a single exception handler, which is responsible for dealing with any uncaught exceptions that make their way to a worker thread's main logic.

By default, all servers are configured to use the [BasicServerExceptionHandler](ddoc-handy_httpd.components.handler.BasicServerExceptionHandler), which is set up to handle [HttpStatusExceptions](ddoc-handy_httpd.components.handler.HttpStatusException) gracefully by setting the response's status accordingly, and for all other exceptions, logs an error message and returns a `500 Internal Server Error` response (if the response headers haven't been flushed yet).

You can add your own exception handler like so:
```d
class CustomExceptionHandler : ServerExceptionHandler {
    void handle(ref HttpRequestContext ctx, Exception e) {
        import std.stdio;
        writeln("Oh no!");
        writeln(e.msg);
    }
}

HttpServer server = new HttpServer(myRequestHandler, myConfig);
server.setExceptionHandler(new CustomExceptionHandler());
server.start();
```

Again, as a matter of principle, your exception handler should do as little as possible, and it **should not** throw any exceptions itself, if you can help it. Any errors that occur inside an exception handler itself will be logged, and no further action can be taken.

Consider having your custom exception handler extend from [BasicServerExceptionHandler](ddoc-handy_httpd.components.handler.BasicServerExceptionHandler), so you can simply override its `handleOtherException` method, while allowing it to handle [HttpStatusExceptions](ddoc-handy_httpd.components.handler.HttpStatusException) for you. Otherwise, you'll probably need to build your own logic for handling HttpStatusExceptions.

## Fatal Errors

It's rare, but you may encounter fatal errors while handling a request, to the tune of segmentation faults, out-of-memory errors, or concurrent modification issues. In such cases, the worker thread that handled that request will die immediately, and the client may or may not receive a coherent response.

Handy-Httpd will try and resurrect dead workers periodically, and it'll warn you each time it does, but it's recommended that you try and address the underlying cause instead of relying on brute-force thread resurrection.

> ⚠️ D programmers are discouraged from catching `Error` or any subclass of it. Most errors are a symptom of unsafe code.
