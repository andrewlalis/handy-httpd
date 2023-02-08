#!/usr/bin/env dub
/+ dub.sdl:
    dependency "handy-httpd" path="../../"
+/
import handy_httpd;
import std.stdio;

const indexContent = `
<html>
    <body>
        <h4>Upload a file!</h4>
        <form action="/upload" method="post" enctype="multipart/form-data">
            <input type="file" name="file1">
            <input type="submit" value="Submit"/>
        </form>
    </body>
</html>
`;

void main() {
    ServerConfig cfg = ServerConfig.defaultValues();
    cfg.workerPoolSize = 3;
    cfg.port = 8080;
    cfg.verbose = true;
    new HttpServer((ref ctx) {
        if (ctx.request.url == "/upload" && ctx.request.method == "POST") {
            if (ctx.request.hasBody) {
                writeln("User uploaded file.\n");
                try {
                    import std.datetime.stopwatch;
                    auto sw = StopWatch(AutoStart.yes);
                    ulong bytesRead = ctx.request.readBodyToFile("latest-upload");
                    sw.stop();
                    writefln!"Read %d bytes in %d ms."(bytesRead, sw.peek.total!"msecs");
                } catch (Exception e) {
                    writeln("Error: " ~ e.msg);
                }
            }
            ctx.response.status = 301;
            ctx.response.addHeader("Location", "/");
        } else if (ctx.request.url == "/" || ctx.request.url == "" || ctx.request.url == "/index.html") {
            ctx.response.writeBody(cast(ubyte[]) indexContent, "text/html; charset=utf-8");
        } else {
            ctx.response.notFound();
        }
    }, cfg).start();
}
