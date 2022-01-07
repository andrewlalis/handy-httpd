module handy_httpd.handlers;

import std.stdio;

import handy_httpd.handler;
import handy_httpd.request;
import handy_httpd.response;
import handy_httpd.responses;

/** 
 * Request handler that resolves files within a given base path.
 */
class FileResolvingHandler : HttpRequestHandler {
    import std.file;
    import std.algorithm.searching;
    import std.string;
    import std.uni;

    private string basePath;

    this(string basePath = ".") {
        this.basePath = basePath;
    }

    HttpResponse handle(HttpRequest request) {
        if (request.url.canFind("/../")) { // Forbid the use of navigating to parent directories.
            return notFound();
        }
        string path = "index.html";
        if (request.url != "/") {
            path = request.url[1..$];
        }
        path = this.basePath ~ "/" ~ path;
        if (!exists(path)) return notFound();
        return fileResponse(path, getMimeType(path));
    }

    private string getMimeType(string filename) {
        string[string] MIME_TYPES = [
            ".html": "text/html",
            ".js": "text/javascript",
            ".css": "text/css",
            ".json": "application/json",
            ".png": "image/png",
            ".jpg": "image/jpg",
            ".gif": "image/gif",
            ".wav": "audio/wav",
            ".ogg": "audio/ogg",
            ".mp3": "audio/mpeg",
            ".mp4": "video/mp4",
            ".woff": "application/font-woff",
            ".ttf": "application/font-ttf",
            ".eot": "application/vnd.ms-fontobject",
            ".otf": "application/font-otf",
            ".svg": "application/image/svg+xml",
            ".wasm": "application/wasm"
        ];
        auto p = filename.lastIndexOf('.');
        if (p == -1) return "text/html";
        string extension = filename[p..$].toLower();
        if (extension !in MIME_TYPES) {
            writefln!"Warning: Unknown mime type for file extension %s"(extension);
            return "text/plain";
        }
        return MIME_TYPES[extension];
    }
}
