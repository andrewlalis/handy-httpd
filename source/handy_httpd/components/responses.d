/** 
 * Contains convenience functions for pre-formatted HTTP responses.
 */
module handy_httpd.components.responses;

import http_primitives : HttpStatus, HttpResponse, writeBodyString, writeBody, flushHeaders;

/** 
 * Formats a response function name into a camelCase name that's suitable for
 * use in mixin-generated code.
 * Params:
 *   name = The name of an HTTP status enum.
 * Returns: The formatted function name.
 */
private string formatResponseFunctionName(string name) {
    import std.string : toLower, capitalize, split, join;
    string[] parts = split(toLower(name), "_");
    string functionName = parts[0];
    for (size_t i = 1; i < parts.length; i++) {
        functionName ~= capitalize(parts[i]);
    }
    return functionName ~ "Response";
}

// Statically generate simple helper functions for each HTTP status.
import std.traits : EnumMembers;

// Generates functions like the following:
// okResponse(ref HttpResponse response) {...}
// okResponse(ref HttpResponse, string bodyContent, string bodyContentType) {...}
// notFoundResponse(ref HttpResponse response) {...}
// notFoundResponse(ref HttpResponse, string bodyContent, string bodyContentType) {...}
static foreach (member; EnumMembers!HttpStatus) {
    import std.string : format;
    mixin(format(
        q{
            void %s(ref HttpResponse response) {
                response.status = HttpStatus.%s;
            }
            
            void %s(
                ref HttpResponse response,
                string bodyContent,
                string bodyContentType = "text/plain; charset=utf-8"
            ) {
                response.status = HttpStatus.%s;
                response.writeBodyString(bodyContent, bodyContentType);
            }
        },
        formatResponseFunctionName(__traits(identifier, member)), member,
        formatResponseFunctionName(__traits(identifier, member)), member
    ));
}

/** 
 * Convenience method to send a file response to a request.
 * Params:
 *   response = The HTTP response to write to.
 *   filename = The filename to send.
 *   type = The mime type to send, such as "text/html; charset=utf-8"
 */
void fileResponse(ref HttpResponse response, string filename, string type) {
    import std.file : exists, getSize;
    import std.conv : to;
    import std.string : toStringz;
    if (!exists(filename)) {
        response.status = HttpStatus.NOT_FOUND;
        response.headers.add("Content-Type", type);
        response.flushHeaders();
    } else {
        response.status = HttpStatus.OK;
        ulong size = getSize(filename);
        // Flush the headers, and begin streaming the file directly.
        import std.stdio : File;
        File inputFile = File(filename);
        response.writeBody(inputFile.byChunk(8192), size, type);
    }
}
