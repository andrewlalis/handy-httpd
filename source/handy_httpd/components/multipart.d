/**
 * Defines data structures and parsing methods for dealing with multipart
 * encoded request bodies.
 */
module handy_httpd.components.multipart;

import handy_httpd.components.request;
import slf4d;
import streams;

struct MultipartElement {
    string name;
    string[string] headers;
    string content;
}

struct MultipartFormData {
    MultipartElement[] elements;
}

class MultipartFormatException : Exception {
    import std.exception : basicExceptionCtors;
    mixin basicExceptionCtors;
}

MultipartFormData readBodyAsMultipartFormData(ref HttpRequest request) {
    import std.algorithm : startsWith, countUntil;
    import std.array;
    import std.typecons;
    string contentType = request.getHeader("Content-Type");
    if (contentType is null || !startsWith(contentType, "multipart/form-data")) {
        throw new MultipartFormatException("Content-Type is not multipart/form-data.");
    }
    ptrdiff_t boundaryIdx = countUntil(contentType, "boundary=");
    if (boundaryIdx < 0) {
        throw new MultipartFormatException("Missing multipart boundary definition.");
    }
    string boundary = contentType[boundaryIdx + "boundary=".length .. $];
    string boundaryNormal = "--" ~ boundary ~ "\r\n";
    string boundaryEnd = "--" ~ boundary ~ "--";
    debugF!"Reading multipart/form-data request body with boundary=%s"(boundary);
    string content = request.readBodyAsString();

    long nextIdx = 0;
    MultipartFormData data;
    RefAppender!(MultipartElement[]) partAppender = appender(&data.elements);
    while (true) {
        string nextBoundary = content[nextIdx .. nextIdx + boundary.length + 4];
        if (nextBoundary == boundaryEnd) {
            traceF!"Found end boundary at %d, finished parsing multipart elements."(nextIdx);
            break;
        } else if (nextBoundary == boundaryNormal) {
            // Find the end index of this element.
            const ulong elementStartIdx = nextIdx + boundary.length + 4;
            const ulong elementEndIdx = elementStartIdx + countUntil(content[elementStartIdx .. $], "--" ~ boundary);
            traceF!"Reading element from body at [%d, %d)"(elementStartIdx, elementEndIdx);
            partAppender ~= readElement(content[elementStartIdx .. elementEndIdx]);
            nextIdx = elementEndIdx;
        } else {
            throw new MultipartFormatException("Invalid boundary: " ~ nextBoundary);
        }
    }
    return data;
}

MultipartElement readElement(string content) {
    import std.algorithm : countUntil;
    import std.string : strip;
    
    MultipartElement element;
    ulong nextHeaderIdx = 0;
    ulong bodyIdx = 0;
    while (true) {
        const ptrdiff_t headerEndIdx = nextHeaderIdx + countUntil(content[nextHeaderIdx .. $], "\r\n");
        string headerContent = content[nextHeaderIdx .. headerEndIdx];
        const ulong headerValueSeparatorIdx = countUntil(headerContent, ":");
        string headerName = strip(headerContent[0 .. headerValueSeparatorIdx]);
        string headerValue = strip(headerContent[headerValueSeparatorIdx + 1 .. $]);
        traceF!"Read part header: %s=%s"(headerName, headerValue);
        element.headers[headerName] = headerValue;
        if (content[headerEndIdx .. headerEndIdx + 4] == "\r\n\r\n") {
            bodyIdx = headerEndIdx + 4;
            break;
        } else {
            nextHeaderIdx = headerEndIdx + 2;
        }
    }
    string bodyContent = content[bodyIdx .. $];

    element.content = bodyContent;

    return element;
}
