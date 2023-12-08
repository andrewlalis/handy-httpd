# Path Delegating Handler

**⚠️ This handler is deprecated in favor of the [PathHandler](./path-handler.md). It will no longer receive any updates, and you should consider switching over to the PathHandler for improved performance and support.**

As you may have read in [Handling Requests](./handling-requests.md), Handy-Httpd offers a pre-made [PathDelegatingHandler](ddoc-handy_httpd.handlers.path_delegating_handler.PathDelegatingHandler) that can match HTTP methods and URLs to specific handlers; a common use case for web servers.

A PathDelegatingHandler is an implementation of [HttpRequestHandler](ddoc-handy_httpd.components.handler.HttpRequestHandler) that will _delegate_ incoming requests to _other_ handlers based on the request's HTTP method and URL. Handlers are registered with the PathDelegatingHandler via one of the overloaded `addMapping` methods.

For example, suppose we have a handler named `userHandler` that we want to invoke on **GET** requests to URLs like `/users/{userId:int}`.

```d
auto userHandler = getUserHandler();
auto pathHandler = new PathDelegatingHandler();
pathHandler.addMapping(Method.GET, "/users/{userId:int}", userHandler);
new HttpServer(pathHandler).start();
```

## Path Patterns

In our example, we used the pattern `/users/{userId:int}`. This is using the PathDelegatingHandler's path pattern specification, which closely resembles so-called "Ant-style" path matchers.

A path pattern is a string that describes a pattern for matching URLs, using the concept of _segments_, where a _segment_ is a section of the URL path. If our URL is `/a/b/c`, its segments are `a`, `b`, and `c`.

The following rules define the path pattern syntax:

- Literal URLs are matched exactly.
- `/*` matches any single segment in the URL.
- `/**` matches zero or more segments in the URL.
- `?` matches any single character in the URL.
- `{varName[:type]}` matches a path variable (optionally of a certain type).

The easiest way to understand how these rules apply are with some examples:

```
Pattern                  Matches                Doesn't Match
-------------------------------------------------------------
/users                   /users                 /users/data

/users/*                 /users/data            /users
                         /users/settings        /users/data/yes

/users/**                /users                 /user
                         /users/data
                         /users/data/settings

/data?                   /datax                 /data
                         /datay                 /dataxyz
                         /dataz

/users/{userId}          /users/123             /users
                         /users/1a2b            /users/123/data

/users/{userId:int}      /users/123             /users/a
                         /users/42              /users/35.2
                         /users/-35

/users/{id:uint}         /users/123             /users/-2
                         /users/42

/users/{name:string}     /users/andrew          /users
                         /users/123
```

### Parameter Types

The following parameter types are built-in to the handler's path pattern parser:

| Name | Description | Regex |
| ---  | ---         | ---   |
| int | A signed integer number. | `-?[0-9]+` |
| uint | An unsigned integer number. | `[0-9]+` |
| string | A series of characters, excluding whitespaces. | `\w+` |
| uuid | A [UUID](https://en.wikipedia.org/wiki/Universally_unique_identifier) string. |Too long |

If you'd like a different pattern, you can use a literal regex instead.

Note that by specifying a type for a path parameter, you guarantee that you can safely call `ctx.request.getPathParamAs!uint("id")` from your handler, and rest assured that it has a value.

