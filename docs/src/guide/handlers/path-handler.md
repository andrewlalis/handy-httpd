# Path Handler

A common use-case for HTTP servers is to serve different content depending on the URL that the user requested. Handy-Httpd accomplishes this with its [PathHandler](ddoc-handy_httpd.handlers.path_handler.PathHandler) that can match HTTP methods (GET, POST, etc.) and URLs to specific handlers.

A PathHandler is an implementation of [HttpRequestHandler](ddoc-handy_httpd.components.handler.HttpRequestHandler) that will *delegate* incoming requests to other handlers based on the request's HTTP method and URL. Handlers are registered with the PathHandler via one of the overloaded `addMapping` methods.

For example, suppose we have a handler named `userHandler` that we want to invoke on **GET** requests to URLs like `/users/:userId:ulong`.

```d
auto pathHandler = new PathHandler()
    .addMapping(Method.GET, "/users/:userId:ulong", userHandler);
new HttpServer(pathHandler).start();
```

## Path Patterns

In our example, we used the pattern `/users/:userId:ulong`. This pattern matches URLs like `/users/<any valid ulong>`. Under the hood, the PathHandler is using the [path-matcher](https://github.com/andrewlalis/path-matcher) library to do matches.

For a complete explanation of how path matching works, check out the path-matcher's README and source code, but we'll include some examples here for completeness' sake.

- `/data` matches the URL `/data` literally, as-is.
- `/data/*` matches the URL `/data/a`, or `/data/1`, or any other single segment under `/data`, but not something like `/data/a/b/c`.
- `/users/:id:ulong` matches `/users/12345`, but not `/users/andrew`.
- `/**` matches any URL.
