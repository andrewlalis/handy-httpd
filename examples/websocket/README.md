# WebSocket Example

This example shows how you can make a simple server to accept websocket connections and listen for messages, and send messages of your own.

Run this example with `dub run --single server.d` (or just `./server.d` if you're on Linux).

Once you've started the example, head to http://localhost:8080 and select the number of websockets to open, then click **Click here to test!** to start the test. The web page will open that many websocket connections to your server, and send/receive some messages.
