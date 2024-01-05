/**
 * Internal queue implementation for incoming socket connections, which is
 * designed for high throughput and thread-safety so that connections can be
 * handed off to many workers concurrently.
 */
module handy_httpd.components.request_queue;

import std.socket : Socket;
import slf4d;

/**
 * The request queue is an interface that defines the basic `enqueue` and
 * `dequeue` methods to add a socket to the queue (the server does this),
 * and remove a socket from the queue (workers do this).
 */
interface RequestQueue {
    /**
     * Adds the given socket to the queue.
     * Params:
     *   s = The socket to add.
     */
    void enqueue(Socket s);

    /**
     * Attempts to remove a socket from the queue. This method may cause the
     * calling thread to block for some amount of time until a socket is
     * available to obtain.
     * Returns: The socket that was removed, or null if none was found.
     */
    Socket dequeue();
}

static immutable uint BLOCKING_DEQUEUE_WAIT_MS = 10_000;

/**
 * A simple array-based queue that uses synchronization to handle concurrent
 * access to the data. The queue is blocked when requests are added, and when
 * they're removed. It's not the best performance, but it just works.
 */
class ConcurrentBlockingRequestQueue : RequestQueue {
    import core.sync.semaphore;

    /// The internal array that holds the queue of sockets.
    private Socket[] queue;
    /// The front(inclusive) and back(exclusive) of the queue.
    private size_t front = 0, back = 0;
    /// The fixed size of the queue.
    private const size_t size;
    /// A semaphore used to notify consumers of items in the queue.
    private Semaphore semaphore;

    /**
     * Constructs the queue with the given size.
     * Params:
     *   queueSize = The size of the queue.
     */
    this(size_t queueSize = 128) {
        this.queue = new Socket[](queueSize);
        this.size = queueSize;
        this.semaphore = new Semaphore();
    }

    /**
     * Adds a socket to the queue, using synchronization on this queue instance
     * for thread-safety.
     * Params:
     *   s = The socket to add to the queue.
     */
    void enqueue(Socket s) {
        bool shouldNotify = false;
        synchronized(this) {
            if (back == size) {
                errorF!"Failed to enqueue a socket for request processing. Too many requests!"();
                return;
            }
            queue[back++] = s;
            shouldNotify = true;
            if (back == size) {
                if (front == 0) {
                    errorF!"The request queue is completely full. Cannot shift contents to make room for more."();
                    return;
                }
                const size_t elements = back - front;
                queue[0 .. elements] = queue[front .. back];
                queue[elements .. $] = null;
                front = 0;
                back = elements;
            }
        }
        if (shouldNotify) semaphore.notify();
    }

    /**
     * Attempts to remove the next available socket from the queue, waiting
     * for a pre-determined time, before timing out. If no socket becomes
     * available, `null` may be returned.
     * Returns: The socket that was dequeued, or null.
     */
    Socket dequeue() {
        import std.datetime : msecs;
        try {
            bool success = semaphore.wait(msecs(BLOCKING_DEQUEUE_WAIT_MS));
            if (success) {
                Socket s;
                synchronized(this) {
                    if (front >= back) return null; // Another thread took it first.
                    s = queue[front];
                    queue[front] = null;
                    front++;
                }
                return s;
            }
        } catch (SyncError e) {
            error("SyncError occurred while waiting for request queue semaphore: " ~ e.msg);
        }
        return null;
    }

    /**
     * Manually notifies this queue's internal semaphore, which might be used
     * to free up any threads that are waiting for a socket, usually used on
     * shutdown.
     */
    void notify() {
        semaphore.notify();
    }
}
