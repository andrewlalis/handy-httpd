/** 
 * Contains convenience functions for pre-formatted HTTP responses.
 * Note that all functions here will flush the response, meaning that you do
 * not have to manually flush the response in your handler.
 */
module handy_httpd.components.responses;

import handy_httpd.components.response;

/** 
 * Convenience method to prepare a simple 200 OK response.
 * Params:
 *    response = The HTTP response to write to.
 */
void okResponse(ref HttpResponse response) {
    response.setStatus(200).setStatusText("OK").flushHeaders();
}

/** 
 * Convenience method to prepare a 200 OK response with a body.
 * Params:
 *   response = The HTTP response to write to.
 *   bodyContent = The body of the response.
 *   contentType = The content type of the body.
 */
void okResponse(ref HttpResponse response, string bodyContent, string contentType = "text/plain") {
    import std.conv : to;
    response.setStatus(200).setStatusText("OK");
    response.addHeader("Content-Type", contentType);
    response.addHeader("Content-Length", bodyContent.length.to!string);
    response.flushHeaders();
    response.clientSocket.send(bodyContent);
}

/** 
 * Convenience method to send a file response to a request.
 * Params:
 *   response = The HTTP response to write to.
 *   filename = The filename to send.
 *   type = The mime type to send, such as "text/html; charset=utf-8"
 */
void fileResponse(ref HttpResponse response, string filename, string type) {
    import std.file;
    import std.stdio;
    import std.conv : to;
    if (!exists(filename)) {
        response.setStatus(404).setStatusText("Not Found")
            .addHeader("Content-Type", type).flushHeaders();
    } else {
        response.setStatus(200).setStatusText("OK")
            .addHeader("Content-Type", type);
        auto file = File(filename, "r");
        ulong size = file.size();
        response.addHeader("Content-Length", size.to!string).flushHeaders();
        // Flush the headers, and begin streaming the file directly.
        foreach (ubyte[] buffer; file.byChunk(16_384)) {
            response.clientSocket.send(buffer);
        }
    }
}

/** 
 * Convenience method to send a 404 Not Found response to a request.
 * Params:
 *   response = The HTTP response to write to.
 */
void notFound(ref HttpResponse response) {
    response.setStatus(404).setStatusText("Not Found").flushHeaders();
}

/** 
 * Convenience method to send a method not allowed response.
 * Params:
 *   response = The response to write to.
 */
void methodNotAllowed(ref HttpResponse response) {
    response.setStatus(405).setStatusText("Method Not Allowed").flushHeaders();
}
