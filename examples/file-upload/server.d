#!/usr/bin/env dub
/+ dub.sdl:
    dependency "handy-httpd" path="../../"
+/
import handy_httpd;
import slf4d;
import slf4d.default_provider;

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
    auto provider = new shared DefaultProvider(true, Levels.TRACE);
    configureLoggingProvider(provider);

    ServerConfig cfg = ServerConfig.defaultValues();
    cfg.workerPoolSize = 3;
    cfg.port = 8080;
    new HttpServer((ref ctx) {
        if (ctx.request.url == "/upload" && ctx.request.method == Method.POST) {
            info("User uploaded file.");
            try {
                MultipartFormData data = readBodyAsMultipartFormData(ctx.request);
                infoF!"Read multipart data:\n%s"(data);
            } catch (Exception e) {
                error(e);
            }
        } else if (ctx.request.url == "/" || ctx.request.url == "" || ctx.request.url == "/index.html") {
            ctx.response.writeBodyString(indexContent, "text/html; charset=utf-8");
        } else {
            ctx.response.setStatus(HttpStatus.NOT_FOUND);
        }
    }, cfg).start();
}
