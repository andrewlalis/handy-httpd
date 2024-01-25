module test;

import handy_httpd;
import slf4d;

import std.datetime;
import std.stdio;
import core.thread;
import core.cpuid;

import requester;

/**
 * Encapsulated logic for a classic speed-test of an HTTP server, where we
 * spawn some threads that each send requests to the server.
 */
class SpeedTest {
    private RequesterThread[] requesters;
    private HttpServer server;
    private Thread serverThread;

    this(HttpServer server, uint requesterCount, LimitType limitType, ulong limit) {
        this.server = server;
        for (uint i = 0; i < requesterCount; i++) {
            requesters ~= new RequesterThread(i, limitType, limit);
        }
    }

    bool run() {
        info("Starting server.");
        serverThread = server.startInNewThread();
        while (!server.isReady) Thread.sleep(msecs(1));
        info("Server is ready to accept requests.");
        const SysTime testStartTime = Clock.currTime();
        foreach (r; requesters) r.start();
        info("Started requester threads.");
        foreach (r; requesters) {
            try {
                r.join();
            } catch (Exception e) {
                error("Failed to join requester thread "~r.name, e);
            }
        }
        const Duration testDuration = Clock.currTime() - testStartTime;
        info("Joined all requester threads.");
        server.stop();
        serverThread.join();
        info("Stopped the server.");
        return showStats(testDuration);
    }

    private bool showStats(Duration testDuration) {
        ulong totalRequests = 0;
        ulong successfulRequests = 0;
        foreach (r; requesters) {
            totalRequests += r.totalRequests;
            successfulRequests += r.totalSuccessfulRequests;
        }
        double successRate = cast(double) successfulRequests / totalRequests;
        const double testDurationMs = testDuration.total!"msecs";
        double requestsPerSecond = successfulRequests / testDurationMs * 1000.0;
        
        writeln("Test Results");
        writeln("------------");
        writefln!"%d requester threads.\n%d server worker threads.\n%d CPU threads.\n"(
            requesters.length,
            server.config.workerPoolSize,
            threadsPerCPU
        );
        writefln!"%d requests\nof which %d were successful,\nfor a success rate of %.5f."(
            totalRequests,
            successfulRequests,
            successRate
        );
        writefln!"%.1f requests per second."(requestsPerSecond);
        return successRate > 0.9999;
    }
}