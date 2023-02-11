# Logging

To ease the process of logging in Handy-Httpd, each [HttpRequestContext](ddoc-handy_httpd.components.handler.HttpRequestContext) comes with a `log` property of the type [ContextLogger](ddoc-handy_httpd.components.logger.ContextLogger) which you can use to log messages while handling a request.

For example:
```d
void handle(ref HttpRequestContext ctx) {
    ctx.log.info("Got request!");
    try {
        doSomethingDangerous();
    } catch (Exception e) {
        ctx.log.errorF!"Uh oh: %s"(e.msg);
    }
    ctx.log.debugF!"Setting response status to %d"(200);
    ctx.response.status = 200;
    ctx.response.writeBodyString("Hello world!");
}
```

All logs written by the context's `log` will *belong* to the worker that is managing this request. If you want a logger with your own custom name instead of the worker, you can do:
```d
auto myLog = ContextLogger.from(ctx.log, "My Custom Logger");
```
The new logger will inherit the logging level from the context's logger.