/**
 * This module defines the worker pool implementation for Handy-Httpd, which
 * is responsible for managing the server's worker threads.
 */
module handy_httpd.components.worker_pool;

import handy_httpd.server;
import handy_httpd.components.config;
import handy_httpd.components.worker;
import core.thread;
import core.atomic;
import core.sync.rwmutex;
import core.sync.semaphore;
import slf4d;

/**
 * A managed pool of worker threads for handling requests to a server. Uses a
 * separate manager thread to periodically check and adjust the pool.
 */
class WorkerPool {
    package HttpServer server;
    package ThreadGroup workerThreadGroup;
    package ServerWorkerThread[] workers;
    package PoolManager managerThread;
    package int nextWorkerId = 1;
    package ReadWriteMutex workersMutex;

    this(HttpServer server) {
        this.server = server;
        this.workerThreadGroup = new ThreadGroup();
        this.managerThread = new PoolManager(this);
        this.workersMutex = new ReadWriteMutex();
    }

    /**
     * Starts the worker pool by spawning new worker threads and a new pool
     * manager thread.
     */
    void start() {
        synchronized(this.workersMutex.writer) {
            while (this.workers.length < this.server.config.workerPoolSize) {
                ServerWorkerThread worker = new ServerWorkerThread(this.server, this.nextWorkerId++);
                worker.start();
                this.workerThreadGroup.add(worker);
                this.workers ~= worker;
            }
        }
        this.managerThread = new PoolManager(this);
        this.managerThread.start();
    }

    /**
     * Stops the worker pool, by stopping all worker threads and the pool's
     * manager thread. After it's stopped, the pool can be started again via
     * `start()`.
     */
    void stop() {
        this.managerThread.stop();
        this.managerThread.notify();
        synchronized(this.workersMutex.writer) {
            this.server.notifyWorkerThreads();
            this.workerThreadGroup.joinAll();
            foreach (worker; this.workers) {
                this.workerThreadGroup.remove(worker);
            }
            this.workers = [];
            this.nextWorkerId = 1;
        }
        this.managerThread.join();
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
 * A thread that's dedicated to checking a worker pool at regular intervals,
 * and correcting any issues it finds.
 */
package class PoolManager : Thread {
    private WorkerPool pool;
    private Logger logger;
    private Semaphore sleepSemaphore;
    private shared bool running;

    package this(WorkerPool pool) {
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
                    deadCount++;
                    this.pool.workerThreadGroup.remove(worker);
                    ServerWorkerThread newWorker = new ServerWorkerThread(this.pool.server, this.pool.nextWorkerId++);
                    newWorker.start();
                    this.pool.workerThreadGroup.add(newWorker);
                    this.pool.workers[idx] = newWorker;
                    this.logger.warnF!
                        "Worker %d died (probably due to an unexpected error), and was replaced by a new worker %d."(
                            worker.id,
                            newWorker.id
                        );
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
    }
}
