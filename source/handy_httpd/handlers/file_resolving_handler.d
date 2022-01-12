module handy_httpd.handlers.file_resolving_handler;

import std.stdio;

import handy_httpd.handler;
import handy_httpd.request;
import handy_httpd.response;
import handy_httpd.responses;

/** 
 * Request handler that resolves files within a given base path.
 */
class FileResolvingHandler : HttpRequestHandler {
    /** 
     * The base path within which to resolve files.
     */
    private string basePath;

    /** 
     * Constructs the request handler.
     * Params:
     *   basePath = The path to use to resolve files in.
     */
    this(string basePath = ".") {
        this.basePath = basePath;
    }

    HttpResponse handle(HttpRequest request) {
        string path = sanitizeRequestPath(request.url);
        if (path == null) return notFound();
        return fileResponse(path, getMimeType(path));
    }

    /** 
     * Sanitizes a request url such that it points to a file within the
     * configured base path for this handler.
     * Params:
     *   url = The url to sanitize.
     * Returns: A string representing the file pointed to by the given url,
     * or null if no valid file could be found.
     */
    private string sanitizeRequestPath(string url) {
        import std.path : buildNormalizedPath;
        import std.file : exists;
        if (url.length == 0 || url == "/") return "index.html";
        string normalized = this.basePath ~ "/" ~ buildNormalizedPath(url[1 .. $]);
        if (normalized[$] == '/') { // Append "index.html" for any directory request.
            normalized ~= "index.html";
        }
        if (!exists(normalized)) return null;
        return normalized;
    }
}

/** 
 * Tries to determine the mime type of a file. Defaults to "text/html" for
 * files of an unknown type.
 * Params:
 *   filename = The name of the file to determine mime type for.
 * Returns: A mime type string.
 */
private string getMimeType(string filename) {
    import std.string : lastIndexOf;
    import std.uni : toLower;
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
