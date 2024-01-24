/**
 * This module defines the worker pool implementation for Handy-Httpd, which
 * is responsible for managing the server's worker threads.
 */
module handy_httpd.components.worker_pool;

import handy_httpd.server;
import handy_httpd.components.config;
import handy_httpd.components.worker;
import handy_httpd.components.parse_utils;
import handy_httpd.components.request_queue;
import handy_httpd.components.worker_pool2 : RequestWorkerPool;

import std.conv;
import std.socket;
import std.typecons;
import core.thread;
import core.atomic;
import core.sync.rwmutex;
import core.sync.semaphore;

import slf4d;
import httparsed;

/**
 * A managed pool of worker threads for handling requests to a server. Uses a
 * separate manager thread to periodically check and adjust the pool.
 */
class LegacyWorkerPool : RequestWorkerPool {
    package HttpServer server;
    package ThreadGroup workerThreadGroup;
    package ServerWorkerThread[] workers;
    package PoolManager managerThread;
    package int nextWorkerId = 1;
    package ReadWriteMutex workersMutex;
    package RequestQueue requestQueue;

    this(HttpServer server) {
        this.server = server;
        this.workerThreadGroup = new ThreadGroup();
        this.managerThread = new PoolManager(this);
        this.workersMutex = new ReadWriteMutex();
        this.requestQueue = new ConcurrentBlockingRequestQueue(server.config.requestQueueSize);
    }

    /**
     * Starts the worker pool by spawning new worker threads and a new pool
     * manager thread.
     */
    void start() {
        synchronized(this.workersMutex.writer) {
            while (this.workers.length < this.server.config.workerPoolSize) {
                ServerWorkerThread worker = new ServerWorkerThread(this.server, this.requestQueue, this.nextWorkerId++);
                worker.start();
                this.workerThreadGroup.add(worker);
                this.workers ~= worker;
            }
        }
        this.managerThread = new PoolManager(this);
        this.managerThread.start();
        debug_("Started the manager thread.");
    }

    /**
     * Stops the worker pool, by stopping all worker threads and the pool's
     * manager thread. After it's stopped, the pool can be started again via
     * `start()`.
     */
    void stop() {
        debug_("Stopping the manager thread.");
        this.managerThread.stop();
        this.managerThread.notify();
        synchronized(this.workersMutex.writer) {
            notifyWorkerThreads();
            try {
                this.workerThreadGroup.joinAll();
            } catch (Exception e) {
                error("An exception was thrown by a joined worker thread.", e);
            }
            debug_("All worker threads have terminated.");
            foreach (worker; this.workers) {
                this.workerThreadGroup.remove(worker);
            }
            this.workers = [];
            this.nextWorkerId = 1;
        }
        try {
            this.managerThread.join();
        } catch (Exception e) {
            error("An exception was thrown when the managerThread was joined.", e);
        }
        debug_("The manager thread has terminated.");
    }

    private void notifyWorkerThreads() {
        ConcurrentBlockingRequestQueue q = cast(ConcurrentBlockingRequestQueue) this.requestQueue;
        for (int i = 0; i < this.server.config.workerPoolSize; i++) {
            q.notify();
            q.notify();
        }
        debug_("Notified all worker threads.");
    }

    void submit(Socket socket) {
        this.requestQueue.enqueue(socket);
    }

    /**
     * Gets the size of the pool, in terms of the number of worker threads.
     * Returns: The number of worker threads in this pool.
     */
    uint size() {
        synchronized(this.workersMutex.reader) {
            return cast(uint) this.workers.length;
        }
    }
}

/**
 * The server worker thread is a thread that processes incoming requests from
 * an `HttpServer`.
 */
class ServerWorkerThread : Thread {
    /**
     * The id of this worker thread.
     */
    public const(int) id;

    /**
     * The reusable request parser that will be called for each incoming request.
     */
    private MsgParser!Msg requestParser = initParser!Msg();

    /**
     * A pre-allocated buffer for receiving data from the client.
     */
    private ubyte[] receiveBuffer;

    /**
     * The server that this worker belongs to.
     */
    private HttpServer server;

    private RequestQueue requestQueue;

    /**
     * A preconfigured SLF4D logger that uses the worker's id in its label.
     */
    private Logger logger;

    /**
     * A shared indicator of whether this worker is currently handling a request.
     */
    private shared bool busy = false;

    /**
     * Constructs this worker thread for the given server, with the given id.
     * Params:
     *   server = The server that this thread belongs to.
     *   id = The thread's id.
     */
    this(HttpServer server, RequestQueue requestQueue, int id) {
        super(&run);
        super.name("handy_httpd_worker-" ~ id.to!string);
        this.id = id;
        this.receiveBuffer = new ubyte[server.config.receiveBufferSize];
        this.server = server;
        this.requestQueue = requestQueue;
        this.logger = getLogger(super.name());
    }

    /**
     * Runs the worker thread. This will run continuously until the server
     * stops. The worker will do the following:
     * 
     * 1. Wait for the next available client.
     * 2. Parse the HTTP request from the client.
     * 3. Handle the request using the server's handler.
     */
    private void run() {
        debug_("Worker started.");
        while (server.isReady) {
            try {
                // First try and get a socket to the client.
                Socket socket = this.requestQueue.dequeue();
                if (socket !is null) {
                    if (!socket.isAlive) socket.close();
                    continue;
                }
                atomicStore(this.busy, true); // Since we got a legit client, mark this worker as busy.
                scope(exit) {
                    atomicStore(this.busy, false);
                }
                handleClient(this.server, socket, this.receiveBuffer, this.requestParser, this.logger);
            } catch (Exception e) {
                logger.error("An unhandled exception occurred in this worker's `run` method.", e);
            }
        }
        debug_("Worker stopped normally after server was stopped.");
    }

    /**
     * Gets a pointer to this worker's internal pre-allocated receive buffer.
     * Returns: A pointer to the worker's receive buffer.
     */
    public ubyte[]* getReceiveBuffer() {
        return &receiveBuffer;
    }

    /**
     * Gets the server that this worker was created for.
     * Returns: The server.
     */
    public HttpServer getServer() {
        return server;
    }

    /**
     * Tells whether this worker is currently busy handling a request.
     * Returns: True if this worker is handling a request, or false otherwise.
     */
    public bool isBusy() {
        return atomicLoad(this.busy);
    }
}

/**
 * A thread that's dedicated to checking a worker pool at regular intervals,
 * and correcting any issues it finds.
 */
package class PoolManager : Thread {
    private LegacyWorkerPool pool;
    private Logger logger;
    private Semaphore sleepSemaphore;
    private shared bool running;

    package this(LegacyWorkerPool pool) {
        super(&run);
        super.name("handy_httpd_worker-pool-manager");
        this.pool = pool;
        this.logger = getLogger(super.name());
        this.sleepSemaphore = new Semaphore();
    }

    private void run() {
        atomicStore(this.running, true);
        while (atomicLoad(this.running)) {
            // Sleep for a while before running checks.
            bool notified = this.sleepSemaphore.wait(msecs(this.pool.server.config.workerPoolManagerIntervalMs));
            if (!notified) {
                this.checkPoolHealth();
            } else {
                // We were notified to quit, exit now.
                this.stop();
            }
        }
    }

    package void notify() {
        this.sleepSemaphore.notify();
    }

    package void stop() {
        atomicStore(this.running, false);
    }

    private void checkPoolHealth() {
        uint busyCount = 0;
        uint waitingCount = 0;
        uint deadCount = 0;
        synchronized(this.pool.workersMutex.writer) {
            for (size_t idx = 0; idx < this.pool.workers.length; idx++) {
                ServerWorkerThread worker = this.pool.workers[idx];
                if (!worker.isRunning()) {
                    // The worker died, so remove it and spawn a new one to replace it.
                    deadCount++;
                    this.pool.workerThreadGroup.remove(worker);
                    ServerWorkerThread newWorker = new ServerWorkerThread(this.pool.server, this.pool.requestQueue, this.pool.nextWorkerId++);
                    newWorker.start();
                    this.pool.workerThreadGroup.add(newWorker);
                    this.pool.workers[idx] = newWorker;
                    this.logger.warnF!
                        "Worker %d died (probably due to an unexpected error), and was replaced by a new worker %d."(
                            worker.id,
                            newWorker.id
                        );

                    // Try to join the thread and report any exception that occurred.
                    try {
                        worker.join(true);
                    } catch (Throwable e) {
                        import std.format : format;
                        if (Exception exc = cast(Exception) e) {
                            logger.error(
                                format!"Worker %d threw an exception."(worker.id),
                                exc
                            );
                        } else {
                            logger.errorF!"Worker %d threw a fatal error: %s"(worker.id, e.msg);
                            throw e;
                        }
                    }
                } else {
                    if (worker.isBusy()) {
                        busyCount++;
                    } else {
                        waitingCount++;
                    }
                }
            }
        }
        this.logger.debugF!"Worker pool: %d busy, %d waiting, %d dead."(busyCount, waitingCount, deadCount);
        if (waitingCount == 0) {
            this.logger.warnF!(
                "There are no worker threads available to take requests. %d are busy. " ~
                "This may be an indication of a deadlock or indefinite blocking operation."
            )(busyCount);
        }
        // Temp check websocket manager health:
        auto manager = pool.server.getWebSocketManager();
        if (manager !is null && !manager.isRunning()) {
            this.logger.error("The WebSocketManager has died! Please report this issue to the author of handy-httpd.");
            pool.server.reviveWebSocketManager();
        }
    }
}
