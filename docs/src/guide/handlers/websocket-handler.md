# WebSocket Handler

The [WebSocketHandler](ddoc-handy_httpd.components.websocket.WebSocketHandler) is a special handler that bridges the gap between HTTP and [Web Sockets](https://en.wikipedia.org/wiki/WebSocket). It only accepts incoming GET requests that contain valid websocket upgrade headers, and, if valid, the client is handed off to the HttpServer's websocket manager to begin receiving and sending messages.

This handler's constructor takes as a single parameter a [WebSocketMessageHandler](ddoc-handy_httpd.components.websocket.WebSocketMessageHandler), which is a class that defines the following methods for handling websocket events:

- `onConnectionEstablished(WebSocketConnection)` - Called after a new websocket connection is established.
- `onTextMessage(WebSocketTextMessage)` - Called when a new text message is received.
- `onBinaryMessage(WebSocketBinaryMessage)` - Called when a new binary message is received.
- `onCloseMessage(WebSocketCloseMessage)` - Called when a CLOSE control message is received, indicating that the client is closing the socket. *Note: This is called before the socket is actually closed!*
- `onConnectionClosed(WebSocketConnection)` - Called after a websocket connection's socket is closed.

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
