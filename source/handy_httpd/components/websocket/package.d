/**
 * Contains the various components of the Handy-Httpd websocket implementation
 * including a request handler, websocket manager thread, and functions for
 * reading and writing websocket data frames.
 */
module handy_httpd.components.websocket;

public import handy_httpd.components.websocket.frame;
public import handy_httpd.components.websocket.handler;
public import handy_httpd.components.websocket.manager;

unittest {
    import slf4d;
    import slf4d.default_provider;
    import streams;

    // auto provider = new shared DefaultProvider(true, Levels.TRACE);
    // configureLoggingProvider(provider);

    ubyte[] example1 = [0x81, 0x05, 0x48, 0x65, 0x6c, 0x6c, 0x6f];
    WebSocketFrame frame1 = receiveWebSocketFrame(arrayInputStreamFor(example1));
    assert(frame1.finalFragment);
    assert(frame1.opcode == WebSocketFrameOpcode.TEXT_FRAME);
    assert(cast(string) frame1.payload == "Hello");

    ubyte[] example2 = [0x81, 0x85, 0x37, 0xfa, 0x21, 0x3d, 0x7f, 0x9f, 0x4d, 0x51, 0x58];
    WebSocketFrame frame2 = receiveWebSocketFrame(arrayInputStreamFor(example2));
    assert(frame2.finalFragment);
    assert(frame2.opcode == WebSocketFrameOpcode.TEXT_FRAME);
    assert(cast(string) frame2.payload == "Hello");

    ubyte[] example3 = [0x01, 0x03, 0x48, 0x65, 0x6c];
    WebSocketFrame frame3 = receiveWebSocketFrame(arrayInputStreamFor(example3));
    assert(!frame3.finalFragment);
    assert(frame3.opcode == WebSocketFrameOpcode.TEXT_FRAME);
    assert(cast(string) frame3.payload == "Hel");

    ubyte[] example4 = [0x80, 0x02, 0x6c, 0x6f];
    WebSocketFrame frame4 = receiveWebSocketFrame(arrayInputStreamFor(example4));
    assert(frame4.finalFragment);
    assert(frame4.opcode == WebSocketFrameOpcode.CONTINUATION);
    assert(cast(string) frame4.payload == "lo");

    ubyte[] pingExample = [0x89, 0x05, 0x48, 0x65, 0x6c, 0x6c, 0x6f];
    WebSocketFrame pingFrame = receiveWebSocketFrame(arrayInputStreamFor(pingExample));
    assert(pingFrame.finalFragment);
    assert(pingFrame.opcode == WebSocketFrameOpcode.PING);
    assert(cast(string) pingFrame.payload == "Hello");

    ubyte[] pongExample = [0x8a, 0x85, 0x37, 0xfa, 0x21, 0x3d, 0x7f, 0x9f, 0x4d, 0x51, 0x58];
    WebSocketFrame pongFrame = receiveWebSocketFrame(arrayInputStreamFor(pongExample));
    assert(pongFrame.finalFragment);
    assert(pongFrame.opcode == WebSocketFrameOpcode.PONG);
    assert(cast(string) pongFrame.payload == "Hello");

    ubyte[] binaryExample1 = new ubyte[256];
    // Populate the data with some expected values.
    for (int i = 0; i < binaryExample1.length; i++) binaryExample1[i] = cast(ubyte) i % ubyte.max;
    ubyte[] binaryExample1Full = cast(ubyte[]) [0x82, 0x7E, 0x01, 0x00] ~ binaryExample1;
    WebSocketFrame binaryFrame1 = receiveWebSocketFrame(arrayInputStreamFor(binaryExample1Full));
    assert(binaryFrame1.finalFragment);
    assert(binaryFrame1.opcode == WebSocketFrameOpcode.BINARY_FRAME);
    assert(binaryFrame1.payload == binaryExample1);

    ubyte[] binaryExample2 = new ubyte[65_536];
    for (int i = 0; i < binaryExample2.length; i++) binaryExample2[i] = cast(ubyte) i % ubyte.max;
    ubyte[] binaryExample2Full = cast(ubyte[]) [0x82, 0x7F, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00] ~
        binaryExample2;
    WebSocketFrame binaryFrame2 = receiveWebSocketFrame(arrayInputStreamFor(binaryExample2Full));
    assert(binaryFrame2.finalFragment);
    assert(binaryFrame2.opcode == WebSocketFrameOpcode.BINARY_FRAME);
    assert(binaryFrame2.payload == binaryExample2);
}
