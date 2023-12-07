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
     * Attempts to remove a socket from the queue.
     * Returns: The socket that was removed, or null if none was found.
     */
    Socket dequeue();
}

/**
 * A simple array-based queue that uses synchronization to handle concurrent
 * access to the data. The queue is blocked when requests are added, and when
 * they're removed. It's not the best performance, but it just works.
 */
class ConcurrentBlockingRequestQueue : RequestQueue {
    import core.sync.semaphore;

    private Socket[] queue;
    private size_t front = 0, back = 0, size = 0;
    private Semaphore semaphore;

    this(size_t queueSize = 128) {
        this.queue = new Socket[](queueSize);
        this.size = queueSize;
        this.semaphore = new Semaphore();
    }

    void enqueue(Socket s) {
        bool shouldNotify = false;
        synchronized {
            if (back == size) {
                errorF!"Failed to enqueue a socket for request processing. Too many requests!"();
                return;
            }
            queue[back++] = s;
            shouldNotify = true;
            if (back == size) {
                debug_("The request queue has reached the end of the array, shifting elements to start.");
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

    Socket dequeue() {
        import std.datetime : msecs;
        try {
            bool success = semaphore.wait(msecs(10_000));
            if (success) {
                Socket s;
                synchronized {
                    s = queue[front];
                    queue[front] = null;
                    front++;
                }
                return s;
            }
        } catch (SyncError e) {
            error("Error occurred while waiting for request queue semaphore.");
            throw e;
        }
        return null;
    }
}
