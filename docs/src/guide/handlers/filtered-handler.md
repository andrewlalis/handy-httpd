# Filtered Handler

The [FilteredRequestHandler](ddoc-handy_httpd.handlers.filtered_handler.FilteredRequestHandler) is a special handler that applies a series of *[filters](ddoc-handy_httpd.handlers.filtered_handler.HttpRequestFilter)* before handling a request, and possibly after a request was handled. This is how we can add middleware-style logic to Handy-Httpd.

Requests to the FilteredRequestHandler are handled like so:

1. Pre-request filters.
2. Call the underlying request handler.
3. Post-request filters.

Let's take a look at the following example, which shows what might be a typical use case for filtered request handling.

```d
HttpRequestHandler myHandler = ...;
auto filteredHandler = new FilteredRequestHandler(
    myHandler,
    // Pre-request filters:
    [new AuthFilter(), new SecurityFilter(), new SpamFilter()],
    // Post-request filters:
    [new AnalyticsFilter(), new ErrorLogFilter()]
);
```

When a new HTTP request comes in, our `filteredHandler` will first call the `AuthFilter`, then the `SecurityFilter`, and finally the `SpamFilter`. If any of these filters fails, then the request handling is over. If all the pre-request filters succeed, then our underlying handler will take care of the request, and we'll move on to the post-request filters. Again, if any filter fails, the handling stops there.

This sort of behavior is governed by the design of the [FilterChain](ddoc-handy_httpd.handlers.filtered_handler.FilterChain). The next section provides a detailed overview of how it works. In fact, the FilteredRequestHandler is nothing more than a filter chain itself!

## The Filter Chain

We use a [FilterChain](ddoc-handy_httpd.handlers.filtered_handler.FilterChain) to organize the list of filters that'll be applied to incoming requests. A FilterChain is just a singly-linked list, with each node containing an [HttpRequestFilter](ddoc-handy_httpd.handlers.filtered_handler.HttpRequestFilter) to apply to a request context.

The [FilterChain.build](ddoc-handy_httpd.handlers.filtered_handler.FilterChain.build) static function can be used to create a FilterChain from a list of filters. Suppose we'd like to create a filter chain that bans certain remote addresses, and then adds a secret header:

```d
class AddrFilter : HttpRequestFilter {
    void apply(ref HttpRequestContext ctx, FilterChain filterChain) {
        if (isValid(ctx.request.remoteAddress)) {
            filterChain.doFilter(ctx);
        } else {
            ctx.response.setStatus(HttpStatus.BAD_REQUEST);
        }
    }
}

class CustomHeaderFilter : HttpRequestFilter {
    void apply(ref HttpRequestContext ctx, FilterChain filterChain) {
        ctx.response.addHeader("SECRET", "Value");
    }
}

// Build a custom filter chain:
FilterChain fc = FilterChain.build([
    new AddrFilter(),
    new CustomHeaderFilter()
]);
// Apply it to a request:
fc.doFilter(ctx);
```
