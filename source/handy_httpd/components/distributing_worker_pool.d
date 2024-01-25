/**
 * A worker pool implementation that uses a dynamic set of workers that each
 * maintain their own queue of requests, while the pool itself distributes
 * requests to any available workers.
 */
module handy_httpd.components.distributing_worker_pool;

import std.socket : Socket;
import core.thread;
import handy_httpd.components.worker_pool : RequestWorkerPool;
import handy_httpd.server : HttpServer;
import slf4d;

/**
 * The distributing worker pool is a request worker pool implementation that
 * tries to distribute work evenly among its workers, with each worker keeping
 * its own internal job queue.
 */
class DistributingWorkerPool : RequestWorkerPool {
    private const size_t workerCount;
    private const size_t receiveBufferSize;

    private Worker[] workers;
    private size_t lastWorkerIdx = 0;
    private uint nextWorkerId = 1;

    this(size_t receiveBufferSize, size_t workerCount) {
        this.receiveBufferSize = receiveBufferSize;
        this.workerCount = workerCount;
    }

    private void addWorker() {
        Worker w = new Worker(nextWorkerId++, receiveBufferSize);
        w.start();
        workers ~= w;
        debugF!"Added worker-%d to the pool."(w.id);
    }

    void start() {
        debug_("Starting the worker pool.");
        while (workers.length < workerCount) {
            addWorker();
        }
        lastWorkerIdx = 0;
    }

    void submit(HttpServer server, Socket socket) {
        uint attempts = 0;
        while (true) {
            if (lastWorkerIdx >= workers.length) lastWorkerIdx = 0;
            if (attempts > 0 && attempts % 1000 == 0) {
                warnF!"Failed to submit socket to a worker in %d attempts."(attempts);
            }
            Worker worker = workers[lastWorkerIdx++];
            if (!worker.isRunning()) {
                onWorkerDied(worker);
            } else if (worker.submit(server, socket)) {
                return; // We successfully submitted the socket to the worker, so quit.
            }
            attempts++; // Otherwise, try again.
        }
    }

    void stop() {
        debug_("Stopping the worker pool.");
        foreach (worker; workers) {
            worker.stop();
            worker.join();
            debugF!"Stopped worker-%d."(worker.id);
        }
        workers.length = 0;
        nextWorkerId = 1;
    }

    private void onWorkerDied(Worker worker) {
        try {
            worker.join();
        } catch (Throwable t) {
            import std.format : format;
            if (Exception e = cast(Exception) t) {
                error(format!"Worker %d threw an exception."(worker.id), e);
            } else {
                errorF!"Worker %d threw a fatal error: %s\n%s"(worker.id, t.msg, t.info);
                throw t;
            }
        }
        // Replace the worker with a new one.
        const uint oldWorkerId = worker.id;
        worker = new Worker(nextWorkerId++, receiveBufferSize);
        worker.start();
        workers[lastWorkerIdx-1] = worker;
        debugF!"Added worker-%d to the pool to replace worker-%d that died."(worker.id, oldWorkerId);
    }
}

private struct ServerJob {
    HttpServer server;
    Socket clientSocket;
} 

private class Worker : Thread {
    import std.conv : to;
    import core.atomic : atomicLoad, atomicStore;
    import core.sync.semaphore : Semaphore;
    import handy_httpd.components.worker : handleClient;
    import handy_httpd.components.parse_utils : Msg;
    import httparsed : MsgParser;

    private const uint id;

    private ubyte[] receiveBuffer;
    private MsgParser!Msg requestParser;

    const size_t JOB_QUEUE_SIZE = 64;
    private ServerJob[JOB_QUEUE_SIZE] jobQueue;
    private size_t queueFront = 0;
    private size_t queueBack = 0;

    private Semaphore semaphore;
    private shared bool busy;
    private shared bool running;

    private Logger logger;

    this(uint id, size_t receiveBufferSize) {
        super(&run);
        this.id = id;
        this.receiveBuffer = new ubyte[receiveBufferSize];
        this.semaphore = new Semaphore();
        this.logger = getLogger("handy_httpd_dist-worker-" ~ id.to!string);
    }

    private void run() {
        atomicStore(running, true);
        while (atomicLoad(running)) {
            bool success = semaphore.wait(msecs(10_000));
            if (success) {
                atomicStore(busy, true);
                scope(exit) {
                    atomicStore(busy, false);
                }
                while (queueFront < queueBack) {
                    ServerJob job = jobQueue[queueFront];
                    jobQueue[queueFront] = ServerJob.init;
                    queueFront++;
                    try {
                        handleClient(
                            job.server,
                            job.clientSocket,
                            receiveBuffer,
                            requestParser,
                            logger
                        );
                    } catch (Exception e) {
                        this.logger.error("An unhandled exception occurred when handling a request.", e);
                        this.logger.error("This worker will now be shut down.");
                        atomicStore(running, false);
                        throw e;
                    }
                }
                // After emptying out the queue, we can reset the indexes.
                queueFront = 0;
                queueBack = 0;
            }
        }
    }

    bool isBusy() {
        return atomicLoad(this.busy);
    }

    bool submit(HttpServer server, Socket socket) {
        if (isBusy) {
            return false;
        }
        if (queueBack == JOB_QUEUE_SIZE) {
            logger.warn("Rejecting submitted socket because the queue is full.");
            return false;
        }
        jobQueue[queueBack++] = ServerJob(server, socket);
        logger.trace("Added a socket to the queue.");
        if (queueBack == JOB_QUEUE_SIZE) {
            // We have filled the queue to capacity.
            if (queueFront == 0) {
                logger.warn("Completely filled socket queue.");
            } else {
                // Shift elements to the start of the array.
                logger.trace("Shifting queued elements to the front of the array.");
                const size_t elements = queueBack - queueFront;
                jobQueue[0..elements] = jobQueue[queueFront..queueBack];
                jobQueue[elements..$] = null;
                queueFront = 0;
                queueBack = elements;
            }
        }
        semaphore.notify();
        logger.trace("Notified the semaphore.");
        return true;
    }

    void stop() {
        atomicStore(running, false);
        semaphore.notify();
        semaphore.notify();
    }
}
