/** 
 * This module defines the `FileResolvingHandler`, which is a pre-built handler
 * you can use to easily serve static file content from a directory.
 */
module handy_httpd.handlers.file_resolving_handler;

import handy_httpd.components.handler;
import handy_httpd.components.request;
import handy_httpd.components.response;
import handy_httpd.components.responses;
import slf4d;

/** 
 * Request handler that resolves files within a given base path. This handler
 * will take the request URL, and try to find a file or directory matching that
 * URL within its configured `basePath`. If a directory is requested, the
 * handler will try to serve an "index" file from it, if such a file exists. If
 * a file is requested, that file will be served, with the appropriate mime
 * type, if it exists.
 *
 * Note that only files strictly within the given `basePath` are able to be
 * served; requests like `/../../data.txt` will result in a 404.
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
            "html": "text/html",
            "md": "text/markdown",
            "txt": "text/plain",
            "js": "text/javascript",
            "css": "text/css",
            "json": "application/json",
            "png": "image/png",
            "jpg": "image/jpg",
            "gif": "image/gif",
            "webp": "image/webp",
            "wav": "audio/wav",
            "ogg": "audio/ogg",
            "mp3": "audio/mpeg",
            "mp4": "video/mp4",
            "woff": "application/font-woff",
            "ttf": "application/font-ttf",
            "eot": "application/vnd.ms-fontobject",
            "otf": "application/font-otf",
            "svg": "application/image/svg+xml",
            "wasm": "application/wasm",
            "pdf": "application/pdf",
            "xml": "application/xml"
        ];
    }

    /**
     * Handles requests for files, where the url points to the file location
     * relative to the base path.
     * Params:
     *   ctx = The request context.
     */
    void handle(ref HttpRequestContext ctx) {
        auto log = getLogger();
        log.debugF!"Resolving file for url %s..."(ctx.request.url);
        string path = sanitizeRequestPath(ctx.request.url);
        if (path !is null) {
            ctx.response.fileResponse(path, getMimeType(path));
        } else {
            log.debugF!"Could not resolve file for url %s."(ctx.request.url);
            ctx.response.notFound();
        }
    }

    /** 
     * Registers a new mime type for this handler.
     * Params:
     *   fileExtension = The file extension to use, excluding the '.' separator.
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
        import std.path;
        import std.file : exists, isDir;
        import std.algorithm : startsWith;
        import std.regex;

        string normalizedUrl;
        if (url.length == 0 || url == "/") {
            return findIndexFile(this.basePath);
        } else {
            if (startsWith(url, "/")) url = url[1 .. $];
            normalizedUrl = buildNormalizedPath(buildPath(this.basePath, url));

            // Ensure that any path outside the base path is ignored.
            string baseAbsolutePath = absolutePath(this.basePath).buildNormalizedPath;
            string normalizedAbsolutePath = absolutePath(normalizedUrl);
            if (!startsWith(normalizedAbsolutePath, baseAbsolutePath)) return null;
        }
        
        if (exists(normalizedUrl)) {
            if (isDir(normalizedUrl)) {
                return findIndexFile(normalizedUrl);
            } else {
                return normalizedUrl;
            }
        } else {
            return null;
        }
    }

    unittest {
        import std.path;
        import std.file;
        import std.stdio;
        
        // For these tests, we'll pretend that the project root dir is our base path for files to serve.
        // For the test, we create a simple "index.html" which is removed at the end.
        auto f = File("index.html", "w");
        f.writeln("<html><body>Hello world.</body></html>");
        f.close();
        scope (exit) {
            if (exists("index.html")) std.file.remove("index.html");
            if (exists("index.htm")) std.file.remove("index.htm");
            if (exists("index.txt")) std.file.remove("index.txt");
            if (exists("index")) std.file.remove("index");
        }
        FileResolvingHandler handler = new FileResolvingHandler(".");
        // Try resolving the base index file when given a URL for the base path.
        assert(handler.sanitizeRequestPath("/") == buildPath(".", "index.html"));
        assert(handler.sanitizeRequestPath("") == buildPath(".", "index.html"));
        // Check that it resolves other common index file types too.
        std.file.rename("index.html", "index.htm");
        assert(handler.sanitizeRequestPath("/") == buildPath(".", "index.htm"));
        std.file.rename("index.htm", "index.txt");
        assert(handler.sanitizeRequestPath("/") == buildPath(".", "index.txt"));
        std.file.rename("index.txt", "index");
        assert(handler.sanitizeRequestPath("/") == buildPath(".", "index"));

        // Check some basic files which exist.
        assert(handler.sanitizeRequestPath("/dub.json") == buildPath("dub.json"));
        assert(
            handler.sanitizeRequestPath("/source/handy_httpd/package.d") ==
            buildPath("source", "handy_httpd", "package.d")
        );
        // Check that non-existent paths resolve to null.
        assert(handler.sanitizeRequestPath("/non-existent-path") is null);
        // Ensure that requests for resources outside the base path are ignored.
        assert(handler.sanitizeRequestPath("/../README.md") is null);
        assert(handler.sanitizeRequestPath("/../../data.txt") is null);
        assert(handler.sanitizeRequestPath("/etc/profile") is null);
    }

    /** 
     * Tries to find a valid "index" file within a directory, to serve in case
     * the file resolving handler gets a request for a directory.
     * Params:
     *   dir = The directory to look in.
     * Returns: The string path to a valid index file, or null if none was found.
     */
    private string findIndexFile(string dir) {
        import std.file : exists;
        import std.path : buildPath;
        string[] possibleIndexFiles = [
            "index.html",
            "index.htm",
            "index.txt",
            "index"
        ];
        foreach (filename; possibleIndexFiles) {
            string path = buildPath(dir, filename);
            if (exists(path)) return path;
        }
        return null;
    }

    unittest {
        import std.path;
        import std.file;
        import std.stdio;

        // Set up a test directory.
        string DIR_NAME = "tmp-findIndexFile";
        mkdir(DIR_NAME);
        scope (exit) {
            if (exists(DIR_NAME)) std.file.rmdirRecurse(DIR_NAME);
        }

        // If no file exists, resolve to null.
        FileResolvingHandler handler = new FileResolvingHandler(DIR_NAME);
        assert(handler.findIndexFile(DIR_NAME) is null);

        string[] possibleFiles = [
            "index.html",
            "index.htm",
            "index.txt",
            "index"
        ];
        foreach (filename; possibleFiles) {
            auto f = File(buildPath(DIR_NAME, filename), "w");
            f.writeln("<html><body>Hello world.</body></html>");
            f.close();
            assert(handler.findIndexFile(DIR_NAME) == buildPath(DIR_NAME, filename));
            std.file.remove(buildPath(DIR_NAME, filename));
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
        auto log = getLogger();
        import std.string : lastIndexOf;
        import std.uni : toLower;
        auto p = filename.lastIndexOf('.');
        if (p == -1) return "text/html";
        string extension = filename[(p + 1)..$].toLower();
        if (extension !in this.mimeTypes) {
            log.warnF!"Unknown mime type for file extension \"%s\"."(extension);
            return "text/html";
        }
        return this.mimeTypes[extension];
    }

    unittest {
        // Setup SLF4D to discard log messages, since some will be emitted by this function.
        import slf4d;
        import slf4d.noop_provider;
        configureLoggingProvider(new NoOpProvider());

        import handy_httpd.components.config;
        FileResolvingHandler handler = new FileResolvingHandler();

        // Check that known mime types work.
        assert(handler.getMimeType("index.html") == "text/html");
        assert(handler.getMimeType("profile.png") == "image/png");
        assert(handler.getMimeType("vid.mp4") == "video/mp4");

        // Check that unknown/missing types resolve to "text/html".
        assert(handler.getMimeType("test.nonexistentextension") == "text/html");
        assert(handler.getMimeType("test") == "text/html");
        assert(handler.getMimeType(".gitignore") == "text/html");
        assert(handler.getMimeType("test.") == "text/html");
    }
}
