module requester;

import std.datetime;
import std.array;
import core.thread;
import slf4d;

enum LimitType {
	RequestCount,
	Time
}

class RequesterThread : Thread {
    const ulong id;
	const LimitType limitType;
	const ulong limit;
	private Logger logger;

	private ulong requestCount;
	private ulong successCount;
	private Appender!(Duration[]) durationAppender;

	this(ulong id, LimitType limitType, ulong limit) {
		super(&this.run);
        this.id = id;
		this.limitType = limitType;
		this.limit = limit;
        import std.format : format;
        this.logger = getLoggerFactory().getLogger(format!"requester-%d"(id));
	}

	private void run() {
		import requests;
		const SysTime testStartTime = Clock.currTime();
		while (
			(limitType == LimitType.RequestCount && requestCount < limit) ||
			(limitType == LimitType.Time && (Clock.currTime() - testStartTime).total!"msecs" < limit)
		) {
			try {
                const SysTime requestStart = Clock.currTime();
				string content = cast(string) getContent("http://localhost:8080/").data;
				durationAppender ~= Clock.currTime() - requestStart;
                if (content == "Testing server") {
					successCount++;
				}
			} catch (Exception e) {
				logger.error(e);
			} finally {
				requestCount++;
			}
		}
        logger.info("Stopped.");
	}

	ulong totalRequests() const {
		return requestCount;
	}

	ulong totalSuccessfulRequests() const {
		return successCount;
	}

	double meanRequestDurationMs() const {
		import std.algorithm;
		return durationAppender.data.map!(d => d.total!"msecs").mean;
	}
}