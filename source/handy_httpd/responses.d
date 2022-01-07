module handy_httpd.responses;

import handy_httpd.response;

/** 
 * Convenience method to prepare a simple 200 OK response.
 * Returns: A 200 OK HTTP response.
 */
HttpResponse okResponse() {
    return HttpResponse(200, "OK", null, []);
}

/** 
 * Convenience method to send a file response to a request.
 * Params:
 *   filename = The filename to send.
 *   type = The mime type to send, such as "text/html; charset=utf-8"
 * Returns: A 200 OK response whose body is the contents of the file that was
 * specified, or 404 Not Found if the file could not be found.
 */
HttpResponse fileResponse(string filename, string type) {
    import std.file;
    if (!exists(filename)) {
        return HttpResponse(404, "Not Found", null, null)
            .addHeader("Content-Type", type);
    } else {
        ubyte[] data = cast(ubyte[]) read(filename);
        return HttpResponse(200, "OK", null, data)
            .addHeader("Content-Type", type);
    }
}

HttpResponse notFound() {
    return HttpResponse(404, "Not Found", null, null);
}

/** 
 * Convenience method to send a method not allowed response.
 * Returns: A 405 Method Not Allowed response.
 */
HttpResponse methodNotAllowed() {
    return HttpResponse(405, "Method Not Allowed", null, null);
}
