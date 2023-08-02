#!/usr/bin/env dub
/+ dub.sdl:
    dependency "handy-httpd" path="../../"
+/
module examples.websocket.server;

import handy_httpd;
import handy_httpd.components.websocket;
import handy_httpd.handlers.path_delegating_handler;
import slf4d;

class MyWebSocketHandler : WebSocketMessageHandler {
    override void handleTextMessage(WebSocketTextMessage msg) {
        infoF!"Got TEXT: %s"(msg.payload);
    }

    override void handleCloseMessage(WebSocketCloseMessage msg) {
        infoF!"Closed: %d, %s"(msg.statusCode, msg.message);
    }
}

void main() {
    ServerConfig cfg = ServerConfig.defaultValues();
    cfg.workerPoolSize = 3;
    PathDelegatingHandler pdh = new PathDelegatingHandler();
    pdh.addMapping(Method.GET, "", (ref HttpRequestContext ctx) {
        ctx.response.writeBodyString("Index page.");
    });
    WebSocketHandler handler = new WebSocketHandler(new MyWebSocketHandler());
    pdh.addMapping(Method.GET, "/ws", handler);
    new HttpServer(pdh, cfg).start();
}
