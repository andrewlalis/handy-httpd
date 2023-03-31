/+ dub.sdl:
    dependency "handy-httpd" path="../../"
+/
module handler;

import handy_httpd;
import std.conv : to, ConvException;
import std.math : sqrt;

// A simple request handler that reads a number from the request body,
// and writes its square root.
class SqrtHandler : HttpRequestHandler {
    void handle(ref HttpRequestContext ctx) {
        string bodyContent = ctx.request.readBodyAsString();
        if (bodyContent is null || bodyContent.length < 1) {
            ctx.response.status = HttpStatus.BAD_REQUEST;
            return;
        }
        try {
            double value = bodyContent.to!double;
            ctx.response.writeBodyString(sqrt(value).to!string);
        } catch (ConvException e) {
            ctx.response.status = HttpStatus.BAD_REQUEST;
        }
    }
}

unittest {
    import handy_httpd;
    import handy_httpd.util.builders;
    import handy_httpd.util.range;
    import std.string;

    auto handler = new SqrtHandler();

    // First test a request that doesn't contain any body.
    auto ctxEmpty = buildCtxForRequest(Method.GET, "/sqrt");
    handler.handle(ctxEmpty);
    assert(ctxEmpty.response.status == HttpStatus.BAD_REQUEST);

    // Then let's test a request that doesn't contain a valid number.
    auto ctxNoNumber = buildCtxForRequest(Method.GET, "/sqrt");
    handler.handle(ctxNoNumber);
    assert(ctxNoNumber.response.status == HttpStatus.BAD_REQUEST);

    // Now let's test a request that should produce the correct output.
    auto responseOutput = new StringOutputRange(); // Use this to store the handler's response.
    auto ctx = new HttpRequestContextBuilder()
        .withRequest((rq) {
            rq.withBody("16");
        })
        .withResponse((rp) {
            rp.withOutputRange(responseOutput);
        })
        .build();
    handler.handle(ctx);
    assert(ctx.response.status == HttpStatus.OK);
    // The response is an HTTP response, so we need to split out the body from the headers.
    string content = responseOutput.content;
    string[] parts = split(content, "\r\n\r\n");
    assert(parts.length == 2);
    assert(parts[1].length > 0);
    assert(strip(parts[1]) == "4");
}
