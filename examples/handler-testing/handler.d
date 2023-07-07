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
    import std.string;
    import streams;

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
    auto sOut = new ResponseCachingOutputStream();
    auto ctx = new HttpRequestContextBuilder()
        .request().withBody("16").and()
        .response().withOutputStream(sOut).and()
        .build();
    handler.handle(ctx);
    assert(ctx.response.status == HttpStatus.OK);
    assert(sOut.getBody() == "4");
}
