# Testing

Handy-Httpd includes a few utilities that make it easy to test your [HttpRequestHandler](ddoc-handy_httpd.components.handler.HttpRequestHandler) without needing to spool up a whole server.

All of the tools can be found in the [handy_httpd.util.builders](ddoc-handy_httpd.util.builders) module.

The [HttpRequestContextBuilder](ddoc-handy_httpd.util.builders.HttpRequestContextBuilder) provides a fluent interface for creating fake request contexts to test your handler. You can see an example of how it's used in [handy-httpd/examples/handler-testing](https://github.com/andrewlalis/handy-httpd/tree/main/examples/handler-testing).
