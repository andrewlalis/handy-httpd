#!/usr/bin/env dub
/+ dub.sdl:
    dependency "handy-httpd" path="../"
+/

/**
 * This example shows how you can manage basic file-upload mechanics using
 * an HTML form and multipart/form-data encoding. In this example, we show a
 * simple form, and when the user uploads some files, a summary of the files
 * is shown.
 */
module examples.file_upload;

import handy_httpd;
import slf4d;
import handy_httpd.handlers.path_handler;

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

void main(string[] args) {
    ServerConfig cfg = ServerConfig.defaultValues;
    if (args.length > 1) {
        import std.conv;
        cfg.port = args[1].to!ushort;
    }
    import slf4d.default_provider;
    auto prov = new shared DefaultProvider(true, Levels.TRACE);
    configureLoggingProvider(prov);
    new HttpServer(new PathHandler()
        .addMapping(Method.GET, "/**", &serveIndex)
        .addMapping(Method.POST, "/upload", &handleUpload),
        cfg
    ).start();
}

void serveIndex(ref HttpRequestContext ctx) {
    ctx.response.writeBodyString(indexContent, "text/html; charset=utf-8");
}

void handleUpload(ref HttpRequestContext ctx) {
    MultipartFormData data = readBodyAsMultipartFormData(ctx.request);
    string response = "File Upload Summary:\n\n";
    foreach (i, MultipartElement element; data.elements) {
        import std.format;
        string filename = element.filename.isNull ? "NULL" : element.filename.get();
        response ~= format!
            "Multipart Element %d of %d:\n\tFilename: %s\n\tSize: %d\n"
            (
                i + 1,
                data.elements.length,
                filename,
                element.content.length
            );
        foreach (string header, string value; element.headers) {
            response ~= format!"\t\tHeader \"%s\": \"%s\"\n"(header, value);
        }
    }
    ctx.response.writeBodyString(response);
}
