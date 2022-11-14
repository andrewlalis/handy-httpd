module handy_httpd.handlers.file_resolving_handler;

import handy_httpd.handler;
import handy_httpd.request;
import handy_httpd.response;
import handy_httpd.responses;
import handy_httpd.logger;

/** 
 * Request handler that resolves files within a given base path.
 */
class FileResolvingHandler : HttpRequestHandler {
    /** 
     * The base path within which to resolve files.
     */
    private string basePath;

    /** 
     * Associative array containing mime type mappings for file extensions.
     */
    private string[string] mimeTypes;

    /** 
     * Constructs the request handler.
     * Params:
     *   basePath = The path to use to resolve files in.
     */
    this(string basePath = ".") {
        this.basePath = basePath;
        this.mimeTypes = [
            ".html": "text/html",
            ".js": "text/javascript",
            ".css": "text/css",
            ".json": "application/json",
            ".png": "image/png",
            ".jpg": "image/jpg",
            ".gif": "image/gif",
            ".webp": "image/webp",
            ".wav": "audio/wav",
            ".ogg": "audio/ogg",
            ".mp3": "audio/mpeg",
            ".mp4": "video/mp4",
            ".woff": "application/font-woff",
            ".ttf": "application/font-ttf",
            ".eot": "application/vnd.ms-fontobject",
            ".otf": "application/font-otf",
            ".svg": "application/image/svg+xml",
            ".wasm": "application/wasm",
            ".pdf": "application/pdf",
            ".txt": "text/plain",
            ".xml": "application/xml"
        ];
    }

    void handle(ref HttpRequest request, ref HttpResponse response) {
        auto log = request.server.getLogger();
        log.infoF!"Resolving file for url %s..."(request.url);
        string path = sanitizeRequestPath(request.url);
        if (path != null) {
            response.fileResponse(path, getMimeType(path, log));
        } else {
            log.infoFV!"Could not resolve file for url %s. Maybe it doesn't exist?"(request.url);
            response.notFound();
        }
    }

    /** 
     * Registers a new mime type for this handler.
     * Params:
     *   fileExtension = The file extension to use, including the '.' separator.
     *   mimeType = The mime type that will be assigned to the given file extension.
     * Returns: The handler, for method chaining.
     */
    public FileResolvingHandler registerMimeType(string fileExtension, string mimeType) {
        mimeTypes[fileExtension] = mimeType;
        return this;
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
        import std.file : exists, isDir;
        import std.regex;
        if (url.length == 0 || url == "/") return this.basePath ~ "/index.html";
        string normalized = this.basePath ~ "/" ~ buildNormalizedPath(url[1 .. $]);
        
        if (!exists(normalized)) return null;
        // If the user has requested a directory, try and serve "index.html" from it.
        if (isDir(normalized)) {
            normalized ~= "/index.html";
            if (!exists(normalized)) return null;
        }
        return normalized;
    }

    /** 
    * Tries to determine the mime type of a file. Defaults to "text/html" for
    * files of an unknown type.
    * Params:
    *   filename = The name of the file to determine mime type for.
    *   log = The logger to use, in case of errors.
    * Returns: A mime type string.
    */
    private string getMimeType(string filename, ServerLogger log) {
        import std.string : lastIndexOf;
        import std.uni : toLower;
        auto p = filename.lastIndexOf('.');
        if (p == -1) return "text/html";
        string extension = filename[p..$].toLower();
        if (extension !in this.mimeTypes) {
            log.infoFV!"Warning: Unknown mime type for file extension %s"(extension);
            return "text/plain";
        }
        return this.mimeTypes[extension];
    }
}
