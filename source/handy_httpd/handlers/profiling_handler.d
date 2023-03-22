module handy_httpd.handlers.profiling_handler;

import handy_httpd.components.handler;
import handy_httpd.components.request;

import std.container : DList;
import std.algorithm;
import std.datetime;

import core.sync.rwmutex;

/** 
 * A wrapper handler that can be applied over another, to record performance
 * statistics at runtime.
 */
class ProfilingHandler : HttpRequestHandler {
    private HttpRequestHandler handler;

    ulong[METHOD_COUNT] methodCounts;

    this(HttpRequestHandler handler) {
        this.handler = handler;
    }

    public void handle(ref HttpRequestContext ctx) {
        import std.datetime.stopwatch;
        StopWatch sw = StopWatch(AutoStart.yes);
        try {
            this.handler.handle(ctx);
        } finally {
            sw.stop();
            RequestInfo info;
            info.timestamp = Clock.currTime();
            info.requestDuration = sw.peek();
            info.requestMethod = ctx.request.method;
            info.responseStatus = ctx.response.status;
            synchronized {
                // Increment method count.
                methodCounts[methodIndex(ctx.request.method)]++;
            }
        }
    }
}

/** 
 * A struct containing information about how a request was handled.
 */
struct RequestInfo {
    SysTime timestamp;
    Duration requestDuration;
    Method requestMethod;
    ushort responseStatus;
}

unittest {
    import handy_httpd.util.builders;
    import core.thread;
    import std.stdio;

    ProfilingHandler h1 = new ProfilingHandler(toHandler((ref HttpRequestContext ctx) {
        // Do nothing
    }));

    // Test method counting.
    auto ctx1 = buildCtxForRequest(Method.GET, "/hello-world");
    h1.handle(ctx1);
    assert(h1.methodCounts[methodIndex(Method.GET)] == 1);
    auto ctx2 = buildCtxForRequest(Method.POST, "/data");
    h1.handle(ctx2);
    assert(h1.methodCounts[methodIndex(Method.POST)] == 1);

    // Test that method counting is thread-safe by handling requests from many threads simultaneously.
    h1.methodCounts[methodIndex(Method.GET)] = 0;
    h1.methodCounts[methodIndex(Method.POST)] = 0;

    class RequesterThread : Thread {
        private Method method;
        private HttpRequestHandler handler;
        public this(Method method, HttpRequestHandler handler) {
            super(&this.run);
            this.method = method;
            this.handler = handler;
        }
        private void run() {
            for (int i = 0; i < 1000; i++) {
                auto c = buildCtxForRequest(this.method, "/hello");
                this.handler.handle(c);
            }
        }
    }

    RequesterThread[] requesterThreads;
    for (int i = 0; i < METHOD_COUNT; i++) {
        const Method method = methodFromIndex(i);
        RequesterThread t = new RequesterThread(method, h1);
        requesterThreads ~= t;
    }
    foreach (t; requesterThreads) t.start();
    foreach (t; requesterThreads) t.join();
    for (int i = 0; i < METHOD_COUNT; i++) {
        assert(h1.methodCounts[i] == 1000);
    }
}
