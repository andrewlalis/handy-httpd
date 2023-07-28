#!/usr/bin/env dub
/+ dub.sdl:
    dependency "handy-httpd" path="../../"
+/
import handy_httpd;
import slf4d;
import slf4d.default_provider;
import handy_httpd.handlers.path_delegating_handler;

const indexContent = `
<html>
    <body>
        <h4>Upload a file!</h4>
        <form action="/upload" method="post" enctype="multipart/form-data">
            <input type="file" name="file1">
            <input type="file" name="file2">
            <input type="file" multiple name="other files">
            <input type="submit" value="Submit"/>
        </form>
    </body>
</html>
`;

void main() {
    auto provider = new shared DefaultProvider(true, Levels.INFO);
    configureLoggingProvider(provider);

    ServerConfig cfg = ServerConfig.defaultValues();
    cfg.workerPoolSize = 3;
    cfg.port = 8080;
    PathDelegatingHandler handler = new PathDelegatingHandler();
    handler.addMapping(Method.GET, "/**", &serveIndex);
    handler.addMapping(Method.POST, "/upload", &handleUpload);
    info("Starting file-upload example server.");
    new HttpServer(handler, cfg).start();
}

void serveIndex(ref HttpRequestContext ctx) {
    ctx.response.writeBodyString(indexContent, "text/html; charset=utf-8");
}

void handleUpload(ref HttpRequestContext ctx) {
    info("User uploaded a file!");
    MultipartFormData data = readBodyAsMultipartFormData(ctx.request);
    infoF!"Read multipart data with %d elements."(data.elements.length);
    foreach (MultipartElement element; data.elements) {
        infoF!"Element name: %s, filename: %s, headers: %s, content-length: %s"(
            element.name,
            element.filename.isNull ? "Null" : element.filename.get(),
            element.headers,
            element.content.length
        );
    }
}
