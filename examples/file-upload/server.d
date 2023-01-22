#!/usr/bin/env dub
/+ dub.sdl:
    dependency "handy-httpd" path="../../"
+/
import handy_httpd;
import std.stdio;
import std.conv;
import std.range;

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

class FileOutputRange : OutputRange!(ubyte[]) {
    private File f;
    this(File f) {
        this.f = f;
    }
    void put(ubyte[] data) {
        f.rawWrite(data);
    }
}

void main() {
    ServerConfig cfg = ServerConfig.defaultValues();
    cfg.workerPoolSize = 5;
    cfg.port = 8080;
    cfg.verbose = true;
    new HttpServer((ref ctx) {
        if (ctx.request.url == "/upload" && ctx.request.method == "POST") {
            writeln(ctx.request);
            if (ctx.request.hasBody) {
                File f = File("out.txt", "w");
                auto r = new FileOutputRange(f);
                ctx.request.readBody(r);
                f.close();
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
