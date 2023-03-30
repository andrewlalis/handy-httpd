/** 
 * Contains convenience functions for pre-formatted HTTP responses.
 */
module handy_httpd.components.responses;

import handy_httpd.components.response;
import handy_httpd.components.handler : HttpRequestContext;
import std.range.interfaces : InputRange;

void respond(
    ref HttpResponse response,
    HttpStatus status,
    InputRange!(ubyte[]) bodyInputRange,
    ulong bodySize,
    string bodyContentType
) {
    response.setStatus(status);
    if (bodyInputRange !is null) {
        response.writeBodyRange(bodyInputRange, bodySize, bodyContentType);
    }
}

void respond(
    ref HttpResponse response,
    HttpStatus status,
    string bodyContent,
    string bodyContentType = "text/plain; charset=utf-8"
) {
    response.setStatus(status);
    if (bodyContent !is null && bodyContent.length > 0) {
        response.writeBodyString(bodyContent, bodyContentType);
    }
}

void respond(ref HttpResponse response, HttpStatus status) {
    respond(response, status, null);
}

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
                response.setStatus(HttpStatus.%s);
            }

            void %s(ref HttpRequestContext ctx) {
                ctx.response.setStatus(HttpStatus.%s);
            }
            
            void %s(
                ref HttpResponse response,
                string bodyContent,
                string bodyContentType = "text/plain; charset=utf-8"
            ) {
                response.setStatus(HttpStatus.%s);
                response.writeBodyString(bodyContent, bodyContentType);
            }

            void %s(
                ref HttpRequestContext ctx,
                string bodyContent,
                string bodyContentType = "text/plain; charset=utf-8"
            ) {
                ctx.response.setStatus(HttpStatus.%s);
                ctx.response.writeBodyString(bodyContent, bodyContentType);
            }
        },
        formatResponseFunctionName(__traits(identifier, member)), member,
        formatResponseFunctionName(__traits(identifier, member)), member,
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
    import std.file;
    import std.stdio;
    import std.conv : to;
    if (!exists(filename)) {
        response.setStatus(HttpStatus.NOT_FOUND);
        response.addHeader("Content-Type", type).flushHeaders();
    } else {
        response.setStatus(HttpStatus.OK);
        auto file = File(filename, "r");
        ulong size = file.size();
        // Flush the headers, and begin streaming the file directly.
        response.writeBodyRange(file.byChunk(8192), size, type);
    }
}
