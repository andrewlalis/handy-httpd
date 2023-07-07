# Testing

Handy-Httpd includes a few utilities that make it easy to test your [HttpRequestHandler](ddoc-handy_httpd.components.handler.HttpRequestHandler) without needing to spool up a whole server.

All of the tools can be found in the [handy_httpd.util.builders](ddoc-handy_httpd.util.builders) module.

The [HttpRequestContextBuilder](ddoc-handy_httpd.util.builders.HttpRequestContextBuilder) provides a fluent interface for creating fake request contexts to test your handler. You can see an example of how it's used in [handy-httpd/examples/handler-testing](https://github.com/andrewlalis/handy-httpd/tree/main/examples/handler-testing).

## Unit Tests

To add unit testing to your Handy-Httpd-based project, you should simply add `unittest` blocks which call your request handlers with various mocked request contexts. This is possible using the [HttpRequestContextBuilder](ddoc-handy_httpd.util.builders.HttpRequestContextBuilder).

Suppose we've got the following request handler that reads a floating-point number from the request body and computes the square root of it, and we want to make sure it works as expected:

```d
void handleSqrt(ref HttpRequestContext ctx) {
    if (ctx.request.method == Method.POST) {
        string content = ctx.request.readBodyAsString();
        import std.conv : to;
        import std.math : sqrt;
        float n = content.to!float;
        float m = sqrt(n);
        ctx.response.writeBodyString(m.to!string);
    } else {
        ctx.response.setStatus(HttpStatus.METHOD_NOT_ALLOWED);
    }
}
```

Then we'd come up with a suite of unit tests that put `handleSqrt` through different scenarios to assert that it behaves as it should.

```d
unittest {
    import handy_httpd.util.builders;
    import std.conv : to;

    auto ctx1 = buildCtxForRequest(Method.GET, "/");
    handleSqrt(ctx1);
    assert(ctx1.response.status == HttpStatus.METHOD_NOT_ALLOWED);

    auto sOut = new ResponseCachingOutputStream();
    auto ctx2 = new HttpRequestContextBuilder()
        .request().withMethod(Method.POST).withBody("16").and()
        .response().withOutputStream(sOut).and()
        .build();
    handleSqrt(ctx2);
    assert(sOut.getBody().to!float == 4.0f);
}
```

In the above code, we used [buildCtxForRequest](ddoc-handy_httpd.util.builders.buildCtxForRequest.1) as a concise way to create a mocked request context. In the second test, we used the [HttpRequestContextBuilder](ddoc-handy_httpd.util.builders.HttpRequestContextBuilder) to build a request context using a fluent method interface, passing a reference to a [ResponseCachingOutputStream](ddoc-handy_httpd.util.builders.ResponseCachingOutputStream) to the context's response, so we can inspect the response body that the handler writes.

Of course, in the real world you'll likely add many more tests than what we've done here, but this is just to give you a feel for how it can be done.

## Integration Tests

Unlike unit tests, Handy-Httpd doesn't provide any additional support for integration tests, partly because we believe that a simple structure and well-tested handlers will solve the vast majority of issues, and also because there are simply too many variables to account for.

Therefore, we recommend that you test your fully-configured server using an external program or suite of tools. You can see some examples in the integration tests for Handy-Httpd itself, where we use a Java program to run file upload and download tests.
