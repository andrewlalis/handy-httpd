module handy_httpd.handlers.profiling_handler;

import handy_httpd.components.handler;
import handy_httpd.components.request;

import std.container : DList;
import std.algorithm;
import std.datetime;

import core.sync.rwmutex;

class ProfilingHandler : HttpRequestHandler {
    private HttpRequestHandler handler;
    private const size_t historyMaxSize;
    private size_t historySize;
    private DList!RequestInfo history;

    this(HttpRequestHandler handler, size_t historyMaxSize = 1000) {
        this.handler = handler;
        this.historyMaxSize = historyMaxSize;
        this.historySize = 0;
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
                this.historySize += this.history.insertFront(info);
                while (this.historySize > this.historyMaxSize) {
                    this.history.removeBack();
                    this.historySize--;
                }
            }
        }
    }

    public double getAverageRequestDuration() {
        return history[].map!(info => info.requestDuration.total!"usecs").mean / 1_000_000.0;
    }

    public double getAverageRequestsPerSecond() {
        if (history.empty) return 0;
        RequestInfo oldestInfo = history.back();
        Duration timeSinceLastInfo = Clock.currTime() - oldestInfo.timestamp;
        return this.historySize / timeSinceLastInfo.total!"seconds";
    }

    public ulong[ushort] getResponseStatusHistogram() {
        ulong[ushort] statuses;
        foreach (info; history) {
            statuses[info.responseStatus]++;
        }
        return statuses;
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

}
