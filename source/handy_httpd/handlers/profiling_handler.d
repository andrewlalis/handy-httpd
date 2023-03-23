module handy_httpd.handlers.profiling_handler;

import handy_httpd.components.handler;
import handy_httpd.components.request;

import std.container : DList;
import std.algorithm;
import std.datetime;

import core.sync.rwmutex;

/** 
 * The default number of request logs to keep, if no trim policy is specified.
 */
private static const size_t DEFAULT_REQUEST_LOG_MAX_COUNT = 10_000;

public HttpRequestHandler profiled(HttpRequestHandler handler, RequestLogTrimPolicy requestLogTrimPolicy) {
    return new ProfilingHandler(handler, requestLogTrimPolicy);
}

public HttpRequestHandler profiled(HttpRequestHandler handler) {
    return profiled(handler, new RequestLogCountTrimPolicy(DEFAULT_REQUEST_LOG_MAX_COUNT));
}

/** 
 * A wrapper handler that can be applied over another, to record performance
 * statistics at runtime.
 */
class ProfilingHandler : HttpRequestHandler {
    private HttpRequestHandler handler;

    private DList!RequestInfo requestLog;
    private size_t requestLogSize;
    private RequestLogTrimPolicy requestLogTrimPolicy;
    private ReadWriteMutex requestLogMutex;

    public this(HttpRequestHandler handler, RequestLogTrimPolicy requestLogTrimPolicy) {
        this.handler = handler;
        this.requestLogTrimPolicy = requestLogTrimPolicy;
        this.requestLogMutex = new ReadWriteMutex();
    }

    public this(HttpRequestHandler handler) {
        this(handler, new RequestLogCountTrimPolicy(DEFAULT_REQUEST_LOG_MAX_COUNT));
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
            synchronized(this.requestLogMutex.writer) {
                this.requestLog.insertFront(info);
                this.requestLogSize++;
                while (this.requestLogTrimPolicy.shouldRemove(this.requestLog.back, this)) {
                    this.requestLog.removeBack();
                    this.requestLogSize--;
                }
            }
        }
    }

    /** 
     * Gets a current snapshot of the profiling handler's request log, for
     * inspection and statistics.
     * Returns: A const array of request logs.
     */
    public const(RequestInfo[]) getRequestLog() {
        import std.range : array;
        synchronized(this.requestLogMutex.reader) {
            return array(this.requestLog[]);
        }
    }

    /** 
     * Clears the request log of all entries.
     */
    public void clearRequestLog() {
        synchronized(this.requestLogMutex.writer) {
            this.requestLog.clear();
        }
    }
}

unittest {
    import handy_httpd.util.builders;
    ProfilingHandler handler = new ProfilingHandler(toHandler((ref HttpRequestContext ctx) {
        ctx.response.status = 200;
        ctx.response.statusText = "OK";
    }));
    // Test that requests are logged.
    auto ctx1 = buildCtxForRequest(Method.GET, "/data");
    handler.handle(ctx1);
    const RequestInfo[] log = handler.getRequestLog();
    assert(log.length == 1);
    assert(log[0].requestMethod == Method.GET);
    assert(log[0].responseStatus == 200);

    // Test that requests are logged in the order they're made.
    auto ctx2 = buildCtxForRequest(Method.POST, "/data");
    handler.handle(ctx2);
    const RequestInfo[] log2 = handler.getRequestLog();
    assert(log2.length == 2);
    assert(log2[0].requestMethod == Method.POST);
    assert(log2[1].requestMethod == Method.GET);

    handler.clearRequestLog();
    const RequestInfo[] log3 = handler.getRequestLog();
    assert(log3.length == 0);
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

/** 
 * A policy for trimming the request log maintained by the ProfilingHandler,
 * so that we don't keep hogging more resources over long runtimes.
 */
interface RequestLogTrimPolicy {
    bool shouldRemove(ref RequestInfo info, ProfilingHandler handler);
}

/** 
 * A policy for trimming old request logs based on a maximum duration, where
 * requests that happened more than X units in the past are removed.
 */
class RequestLogTimeTrimPolicy : RequestLogTrimPolicy {
    private const Duration duration;

    public this(Duration duration) {
        this.duration = duration;
    }

    public bool shouldRemove(ref RequestInfo info, ProfilingHandler handler) {
        SysTime now = Clock.currTime();
        Duration timeElapsed = now - info.timestamp;
        return timeElapsed > this.duration;
    }
}

/** 
 * A policy for trimming old request logs based on a maximum allowable count of
 * requests, such that if there are more than the maximum number of requests,
 * the oldest will be removed.
 */
class RequestLogCountTrimPolicy : RequestLogTrimPolicy {
    private const size_t maxCount;
    
    public this(size_t maxCount) {
        this.maxCount = maxCount;
    }

    public bool shouldRemove(ref RequestInfo info, ProfilingHandler handler) {
        return handler.requestLogSize > this.maxCount;
    }
}

unittest {
    import handy_httpd.util.builders;
    import core.thread;
    ProfilingHandler handler = new ProfilingHandler(toHandler((ref ctx) {
        ctx.response.status = 200;
    }), new RequestLogCountTrimPolicy(10));

    for (int i = 0; i < 10; i++) {
        auto ctx = buildCtxForRequest(Method.GET, "/data");
        handler.handle(ctx);
        Thread.sleep(hnsecs(1)); // Sleep to ensure that timestamps are sufficiently spaced.
    }

    auto log = handler.getRequestLog();
    assert(log.length == 10);
    assert(log[0].timestamp > log[9].timestamp);

    // Test that adding one more request than what's allowed, will evict the oldest log.
    auto ctx = buildCtxForRequest(Method.POST, "/data");
    handler.handle(ctx);
    auto log2 = handler.getRequestLog();
    assert(log2.length == 10);
    assert(log2[0].requestMethod == Method.POST);
}
