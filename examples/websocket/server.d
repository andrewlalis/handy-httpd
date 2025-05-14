#!/usr/bin/env dub
/+ dub.sdl:
    dependency "handy-httpd" path="../../"
+/
module examples.websocket.server;

import handy_httpd;
import handy_httpd.components.websocket;
import handy_httpd.handlers.path_handler;
import handy_httpd.handlers.file_resolving_handler;
import slf4d;

class MyWebSocketHandler : WebSocketMessageHandler {
    override void onConnectionEstablished(WebSocketConnection conn, in HttpRequest request) {
        infoF!"Connection established with id %s"(conn.id);
    }

    override void onTextMessage(WebSocketTextMessage msg) {
        infoF!"Got TEXT: %s"(msg.payload);
        msg.conn.sendTextMessage("Hey yourself!");
    }

    override void onCloseMessage(WebSocketCloseMessage msg) {
        infoF!"Closed: %d, %s"(msg.statusCode, msg.message);
    }
}

void main(string[] args) {
    ServerConfig cfg;
    if (args.length > 1) {
        import std.conv;
        cfg.port = args[1].to!ushort;
    }
    cfg.workerPoolSize = 3;
    cfg.enableWebSockets = true; // Important! Websockets won't work unless `enableWebSockets` is set to true!
    WebSocketHandler handler = new WebSocketHandler(new MyWebSocketHandler());
    PathHandler pathHandler = new PathHandler()
        .addMapping(Method.GET, "/ws", handler)
        .addMapping("/**", new FileResolvingHandler("site"));
    new HttpServer(pathHandler, cfg).start();
}
