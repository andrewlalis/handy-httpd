# Profiling Handler

The [ProfilingHandler](ddoc-handy_httpd.handlers.profiling_handler.ProfilingHandler) wraps around your existing [HttpRequestHandler](ddoc-handy_httpd.components.handler.HttpRequestHandler) to record performance data for each request that's handled.

With each request that's handled, some information about it is collected: how long it took to process, the request method, response status, and so on. This data is then forwarded to a [ProfilingDataHandler](ddoc-handy_httpd.handlers.profiling_handler.ProfilingDataHandler) for further processing.

Generally, you can swap in a ProfilingHandler as a drop-in wrapper around your original handler, and begin collecting profiling information from it.

Suppose you've made a request handler like the one below, and you want to profile its performance. Simply wrap it in a ProfilingHandler, and supply a data handler to deal with the profiling data that's emitted.

```d
// Suppose you have this handler
class MyHandler : HttpRequestHandler {
    void handle(ref HttpRequestContext ctx) {
        ctx.response.status = HttpStatus.OK;
        ctx.response.writeBodyString("Hello there!");
    }
}

void main() {
    import handy_httpd.handlers.profiling_handler;
    new HttpServer(profiled(new MyHandler())).start();
}
```

## Data Handlers

While you can, and probably should create your own [ProfilingDataHandler](ddoc-handy_httpd.handlers.profiling_handler.ProfilingDataHandler), Handy-Httpd ships with a few that are ready to use out-of-the-box, if you just want to get started and play around with some stats.

### Logging Data Handler

The [LoggingProfilingDataHandler](ddoc-handy_httpd.handlers.profiling_handler.LoggingProfilingDataHandler) will emit messages to the application's [SLF4D](https://github.com/andrewlalis/slf4d) logging system. It will emit a short message for each request that's handled, as well as occasionally a more detailed message with some aggregate data from the last few requests.

> This is the default data handler that's used if you don't specify one when wrapping your request handler with the [profiled](ddoc-handy_httpd.handlers.profiling_handler.profiled) function.

```d
import handy_httpd.handlers.profiling_handler;
import slf4d : Levels;
HttpRequestHandler wrappedHandler = profiled(
    new MyHandler(),
    new LoggingProfilingDataHandler(
        Levels.INFO, // The logging level to output messages at.
        25, // Send a detailed message once per 25 requests.
        500 // Keep the last 500 requests cached for stats.
    )
);
```

### CSV Data Handler

The [CsvProfilingDataHandler](ddoc-handy_httpd.handlers.profiling_handler.CsvProfilingDataHandler) writes all request data to a CSV file so that you can process it later however you like.

```d
import handy_httpd.handlers.profiling_handler;
HttpRequestHandler wrappedHandler = profiled(
    new MyHandler(),
    new CsvProfilingDataHandler("MyHandler-profiling.csv")
);
```

Here's a sample of what that CSV data looks like:

```csv
TIMESTAMP, DURATION_HECTONANOSECONDS, REQUEST_METHOD, RESPONSE_STATUS
2023-03-23T23:29:35.0386197, 5, DELETE, 200
2023-03-23T23:29:35.0386406, 2, HEAD, 200
2023-03-23T23:29:35.038647, 14, DELETE, 200
2023-03-23T23:29:35.0386532, 230, GET, 200
```

> Note that the specified CSV file will be overwritten if it already exists.

## Thread Safety and Performance

Because of the fact that an HttpRequestHandler may be invoked from multiple worker threads, a profiler's data handler may therefore have its `handle` method invoked from multiple threads. You should be aware of this for two main reasons:

- When creating your own ProfilingDataHandler, you may need to use a mutex or `synchronized` block to avoid concurrency issues.
- Wrapping your request handler in a ProfilingHandler may lead to performance bottlenecks if your data handler needs to synchronize access to resources.

With that in mind, the ProfilingHandler should be used as a tool to measure performance and other patterns for a particular handler, but should probably not be a permanent part of how you build your server.
