# WebSocket Handler

The [WebSocketHandler](ddoc-handy_httpd.components.websocket.WebSocketHandler) is a special handler that bridges the gap between HTTP and [Web Sockets](https://en.wikipedia.org/wiki/WebSocket). It only accepts incoming GET requests that contain valid websocket upgrade headers, and, if valid, the client is handed off to the HttpServer's websocket manager to begin receiving and sending messages.

This handler's constructor takes as a single parameter a [WebSocketMessageHandler](ddoc-handy_httpd.components.websocket.WebSocketMessageHandler), which is a class that defines the following methods for handling websocket events:

- [onConnectionEstablished](ddoc-handy_httpd.components.websocket.WebSocketMessageHandler.onConnectionEstablished) is called after a new websocket connection is established.
- [onTextMessage](ddoc-handy_httpd.components.websocket.WebSocketMessageHandler.onTextMessage) is called when a new text message is received.
- [onBinaryMessage](ddoc-handy_httpd.components.websocket.WebSocketMessageHandler.onBinaryMessage) is called when a new binary message is received.
- [onCloseMessage](ddoc-handy_httpd.components.websocket.WebSocketMessageHandler.onCloseMessage) is called when a CLOSE control message is received, indicating that the client is closing the socket. *Note: This is called before the socket is actually closed!*
- [onConnectionClosed](ddoc-handy_httpd.components.websocket.WebSocketMessageHandler.onConnectionClosed) is called after a websocket connection's socket is closed.

To write your own websocket handler, simply create a new class that extends from `WebSocketMessageHandler`, and override the methods you'd like to deal with. Here's an example where we make a simple message handler that prints out text messages:

```d
import handy_httpd;

class Printer : WebSocketMessageHandler {
    override void onTextMessage(WebSocketTextMessage msg) {
        import std.stdio;
        writeln(msg.payload);
    }
}

void main() {
    auto handler = new WebSocketHandler(new Printer());
    new HttpServer(handler).start();
}
```

## Sending Messages

We've seen how you can receive messages, but it's also important to be able to send messages back to the client, at any time. There are a few ways to do this:

1. In each of the methods of [WebSocketMessageHandler](ddoc-handy_httpd.components.websocket.WebSocketMessageHandler), you can get a reference to a [WebSocketConnection](ddoc-handy_httpd.components.websocket.WebSocketConnection), which contains methods for sending messages back to the client that sent the message. Each type of `WebSocket...Message` contains a reference to the connection, by the way.
2. Use the server's [WebSocketManager](ddoc-handy_httpd.components.websocket.WebSocketManager) to broadcast a message to all connected clients. You can obtain the manager anywhere that you've got access to the server via [getWebSocketManager](ddoc-handy_httpd.server.HttpServer.getWebSocketManager). For example, in a normal [HttpRequestHandler](ddoc-handy_httpd.components.handler.HttpRequestHandler).
3. In your WebSocketHandler's [onConnectionEstablished](ddoc-handy_httpd.components.websocket.WebSocketMessageHandler.onConnectionEstablished) method, save a reference to the new connection somewhere, so you can call upon its send methods later. You can remove this reference once the connection is closed via [onConnectionClosed](ddoc-handy_httpd.components.websocket.WebSocketMessageHandler.onConnectionClosed).

## Implementation Details

Unlike Handy-Httpd's normal thread-per-connection model for handling short-lived HTTP requests, websockets are handled in a nonblocking fashion by a single [WebSocketManager](ddoc-handy_httpd.components.websocket.WebSocketManager) thread, which is activated upon starting the server.

Therefore, all websocket messages are handled from the same thread, and you should take care to avoid operations that may cause the thread to wait or halt, as this will deteriorate other connections. If you need to do something like that, spawn a new thread to do the work asynchronously, or use D's [std.parallelism](https://dlang.org/phobos/std_parallelism.html) module to submit tasks to a task pool.
