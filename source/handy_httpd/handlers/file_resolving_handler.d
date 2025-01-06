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
     * The strategy that this handler uses when resolving requests for directories.
     */
    private const DirectoryResolutionStrategy directoryResolutionStrategy;

    /** 
     * Associative array containing mime type mappings for file extensions.
     */
    private string[string] mimeTypes;

    /** 
     * Constructs the request handler.
     * Params:
     *   basePath = The path to use to resolve files in.
     *   directoryResolutionStrategy = The strategy to use when resolving
     *                                 requests for directories.
     */
    this(
        string basePath = ".",
        DirectoryResolutionStrategy directoryResolutionStrategy
            = DirectoryResolutionStrategies.listDirContentsAndServeIndexFiles
    ) {
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
            "svg": "image/svg+xml",
            "wav": "audio/wav",
            "ogg": "audio/ogg",
            "mp3": "audio/mpeg",
            "mp4": "video/mp4",
            "woff": "application/font-woff",
            "ttf": "application/font-ttf",
            "eot": "application/vnd.ms-fontobject",
            "otf": "application/font-otf",
            "wasm": "application/wasm",
            "pdf": "application/pdf",
            "xml": "application/xml"
        ];
        this.directoryResolutionStrategy = directoryResolutionStrategy;
    }

    /**
     * Handles requests for files, where the url points to the file location
     * relative to the base path.
     * Params:
     *   ctx = The request context.
     */
    void handle(ref HttpRequestContext ctx) {
        import std.file : isFile, isDir;

        auto log = getLogger();
        log.debugF!"Resolving file for URL %s"(ctx.request.url);
        string path = sanitizeRequestPath(ctx.request.url);
        log.traceF!"Sanitized URL %s to path %s"(ctx.request.url, path);
        if (path !is null) {
            if (isFile(path)) {
                log.debugF!"Sending file response from path %s"(path);
                ctx.response.fileResponse(path, getMimeType(path));
            } else if (isDir(path)) {
                log.debugF!"Handling request for directory %s"(path);
                handleDirRequest(ctx.response, path, ctx.request.url);
            } else {
                log.debugF!"Path %s is not a file or directory."(path);
                ctx.response.status = HttpStatus.NOT_FOUND;
            }
        } else {
            log.debugF!"Could not resolve file for url %s."(ctx.request.url);
            ctx.response.status = HttpStatus.NOT_FOUND;
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
     * Sanitizes a request url such that it points to a file or directory
     * within the handler's configured base path.
     * Params:
     *   url = The url to sanitize.
     * Returns: A string representing the file pointed to by the given url,
     * or null if no valid file or directory could be found.
     */
    private string sanitizeRequestPath(string url) {
        import std.path : buildPath, buildNormalizedPath, absolutePath;
        import std.file : exists;
        import std.algorithm : startsWith;

        string normalizedUrl;
        if (url.length == 0 || url == "/") {
            return this.basePath;
        } else {
            if (startsWith(url, "/")) url = url[1 .. $];
            normalizedUrl = buildNormalizedPath(buildPath(this.basePath, url));

            // Ensure that any path outside the base path is ignored.
            string baseAbsolutePath = absolutePath(this.basePath).buildNormalizedPath;
            string normalizedAbsolutePath = absolutePath(normalizedUrl);
            if (!startsWith(normalizedAbsolutePath, baseAbsolutePath)) return null;
        }

        return exists(normalizedUrl) ? normalizedUrl : null;
    }

    unittest {
        import std.path : buildPath;
        
        // For these tests, we'll pretend that the project root dir is our base path for files to serve.
        FileResolvingHandler handler = new FileResolvingHandler(".");
        assert(handler.sanitizeRequestPath("/") == buildPath("."));
        assert(handler.sanitizeRequestPath("") == buildPath("."));

        // Check some basic files which exist.
        assert(handler.sanitizeRequestPath("/dub.json") == buildPath("dub.json"));
        assert(
            handler.sanitizeRequestPath("/source/handy_httpd/package.d") ==
            buildPath("source", "handy_httpd", "package.d")
        );
        assert(handler.sanitizeRequestPath("/examples") == buildPath("examples"));
        // Check that non-existent paths resolve to null.
        assert(handler.sanitizeRequestPath("/non-existent-path") is null);
        // Ensure that requests for resources outside the base path are ignored.
        assert(handler.sanitizeRequestPath("/../README.md") is null);
        assert(handler.sanitizeRequestPath("/../../data.txt") is null);
        assert(handler.sanitizeRequestPath("/etc/profile") is null);
    }

    /** 
     * Handles a request for a directory. What happens depends on the directory
     * resolution strategy of this handler. If we are allowed to serve index
     * files, then we'll try to do that. Otherwise, if we're allowed to show a
     * listing of directory contents, we'll do that. Finally, if neither of
     * those options are allowed, we return a 404.
     * Params:
     *   response = The response to write to.
     *   dir = The directory that was requested.
     *   requestUrl = The original request URL.
     */
    private void handleDirRequest(ref HttpResponse response, string dir, string requestUrl) {
        if (directoryResolutionStrategy.serveIndexFiles) {
            string indexFilePath = findIndexFile(dir);
            if (indexFilePath !is null) {
                fileResponse(response, indexFilePath, getMimeType(indexFilePath));
                return;
            }
        }
        if (directoryResolutionStrategy.listDirContents) {
            import std.array : appender;
            import std.file : dirEntries, SpanMode;
            import std.format : format;
            import std.path : buildPath, baseName;

            string html = q"HTML
<html>
<body>
    <h3>Entries for directory "%s"</h3>
    <table>
        <tr>
            <th>Entry</th>
            <th>Type</th>
            <th>Last Modified</th>
            <th>Size</th>
        </tr>
        %s
    </table>
</body>
HTML";
            auto app = appender!string;

            foreach (entry; dirEntries(dir, SpanMode.shallow, false)) {
                string rowFormat = q"HTML
<tr>
    <td><a href="%s">%s</a></td>
    <td>%s</td>
    <td>%s</td>
    <td>%d</td>
</tr>
HTML";
                string filename = baseName(entry.name);
                string fileUrl = buildPath(requestUrl, filename);
                app ~= format(
                    rowFormat,
                    fileUrl, filename,
                    entry.isFile() ? "file" : "dir",
                    entry.timeLastModified(),
                    entry.size()
                );
            }

            response.writeBodyString(format(html, requestUrl, app[]), "text/html");
            return;
        }
        // No other option but to return not-found.
        response.status = HttpStatus.NOT_FOUND;
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
        import std.string : lastIndexOf;
        import std.uni : toLower;
        auto p = filename.lastIndexOf('.');
        if (p == -1) return "text/html";
        string extension = filename[(p + 1)..$].toLower();
        if (extension !in this.mimeTypes) {
            return "text/html";
        }
        return this.mimeTypes[extension];
    }

    unittest {
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

struct DirectoryResolutionStrategy {
    /** 
     * Whether to show a plain HTML listing of the directory's content.
     */
    public const bool listDirContents;
    /** 
     * Whether to attempt to serve index files from a directory.
     */
    public const bool serveIndexFiles;
}

enum DirectoryResolutionStrategies {
    listDirContentsAndServeIndexFiles = DirectoryResolutionStrategy(true, true),
    listDirContents = DirectoryResolutionStrategy(true, false),
    serveIndexFiles = DirectoryResolutionStrategy(false, true),
    none = DirectoryResolutionStrategy(false, false)
}
