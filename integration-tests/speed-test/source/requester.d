module requester;

import std.datetime;
import core.thread;
import slf4d;

class RequesterThread : Thread {
    const ulong id;
	ulong requestCount;
	ulong successCount;
	bool running;

    Logger logger;

	this(ulong id) {
		super(&this.run);
        this.id = id;
        import std.format : format;
        this.logger = getLoggerFactory().getLogger(format!"requester-%d"(id));
	}

	private void run() {
		import requests;

        logger.info("Starting.");
		running = true;
		while (isActive()) {
			try {
                logger.debug_("Fetching content...");
                SysTime requestStart = Clock.currTime();
				string content = cast(string) getContent("http://localhost:8080/").data;
				Duration dur = Clock.currTime() - requestStart;
                logger.debugF!"Got response in %d ms."(dur.total!"msecs");
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

	public void shutdown() {
		synchronized {
			running = false;
		}
		logger.debug_("shutdown() called.");
	}

	bool isActive() {
		synchronized {
			return running;
		}
	}
}