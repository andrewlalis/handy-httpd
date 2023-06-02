/** 
 * Contains HTTP request components.
 */
module handy_httpd.components.request;

import handy_httpd.server: HttpServer;
import handy_httpd.components.response : HttpResponse;
import std.typecons : Nullable, nullable;
import std.exception;
import slf4d;
import streams;

/** 
 * The data which the server provides to HttpRequestHandlers so that they can
 * formulate a response.
 */
struct HttpRequest {
    /** 
     * The HTTP method verb, such as GET, POST, PUT, etc. This is internally
     * defined as a bit-shifted 1, for efficient matching logic. See the
     * `Method` enum in this module for more information.
     */
    public const Method method = Method.GET;

    /** 
     * The url of the request, excluding query parameters.
     */
    public const string url = "";

    /** 
     * The request version.
     */
    public const int ver = 1;

    /** 
     * An associative array containing all request headers.
     */
    public const string[string] headers;

    /** 
     * An associative array containing all request params, if any were given.
     */
    public const string[string] params;

    /**
     * An associative array containing any path parameters obtained from the
     * request url. These are only populated in cases where it is possible to
     * parse path parameters, such as with a PathDelegatingHandler.
     */
    public string[string] pathParams;

    /**
     * The input stream for the request's body. This may be `null` if the
     * request doesn't have a body.
     */
    public InputStream!ubyte inputStream;

    /**
     * The pre-allocated buffer that we'll use when receiving the rest of this
     * request's body, if it has one. This buffer belongs to the worker that
     * is handling the request.
     */
    public ubyte[] receiveBuffer;

    /** 
     * Tests if this request has a header with the given name.
     * Params:
     *   name = The name to check for, case-sensitive.
     * Returns: True if this request has a header with the given name, or false
     * otherwise.
     */
    public bool hasHeader(string name) {
        return (name in headers) !is null;
    }

    /** 
     * Gets the string representation of a given header value, or null if the
     * header isn't present.
     * Params:
     *   name = The name of the header, case-sensitive.
     * Returns: The header's string representation, or null if not found.
     */
    public string getHeader(string name) {
        if (hasHeader(name)) return headers[name];
        return null;
    }

    /** 
     * Gets a header as the specified type, or returns the default value
     * if the header with the given name doesn't exist or is of an invalid
     * format.
     * Params:
     *   name = The name of the header, case-sensitive.
     *   defaultValue = The default value to return if the header doesn't exist.
     * Returns: The value of the header as the specified type.
     */
    public T getHeaderAs(T)(string name, T defaultValue = T.init) {
        import std.conv : to, ConvException;
        if (!hasHeader(name)) return defaultValue;
        try {
            return headers[name].to!T;
        } catch (ConvException e) {
            return defaultValue;
        }
    }

    /** 
     * Gets a URL parameter as the specified type, or returns the default value
     * if the parameter with the given name doesn't exist or is of an invalid
     * format.
     * Params:
     *   name = The name of the URL parameter.
     *   defaultValue = The default value to return if the URL parameter
     *                  doesn't exist.
     * Returns: The value of the URL parameter.
     */
    public T getParamAs(T)(string name, T defaultValue = T.init) {
        import std.conv : to, ConvException;
        if (name !in params) return defaultValue;
        try {
            return params[name].to!T;
        } catch (ConvException e) {
            return defaultValue;
        }
    }

    unittest {
        HttpRequest req = HttpRequest(
            Method.GET,
            "/api",
            1,
            string[string].init,
            [
                "a": "123",
                "b": "c",
                "c": "true"
            ],
            string[string].init
        );
        assert(req.getParamAs!int("a") == 123);
        assert(req.getParamAs!char("b") == 'c');
        assert(req.getParamAs!bool("c") == true);
        assert(req.getParamAs!int("d") == 0);
    }

    /** 
     * Gets a path parameter as the specified type, or returns the default
     * value if the path parameter with the given name doesn't exist or is
     * of an invalid format.
     * Params:
     *   name = The name of the path parameter.
     *   defaultValue = The default value to return if the path parameter
     *                  doesn't exist.
     * Returns: The value of the path parameter.
     */
    public T getPathParamAs(T)(string name, T defaultValue = T.init) const {
        import std.conv : to, ConvException;
        if (name !in pathParams) return defaultValue;
        try {
            return pathParams[name].to!T;
        } catch (ConvException e) {
            return defaultValue;
        }
    }

    unittest {
        HttpRequest req = HttpRequest();
        req.pathParams = [
            "a": "123",
            "b": "c",
            "c": "true"
        ];
        assert(req.getPathParamAs!int("a") == 123);
        assert(req.getPathParamAs!char("b") == 'c');
        assert(req.getPathParamAs!bool("c") == true);
        assert(req.getPathParamAs!int("d") == 0);
    }

    /** 
     * Reads the entirety of the request body, and passes it to the given
     * output stream.
     *
     * Throws an exception if the connection is closed before the expected
     * data can be read (if a Content-Length header is given).
     *
     * Params:
     *   outputStream = An output byte stream to write the body to.
     *   allowInfiniteRead = Whether to allow the function to read potentially
     *                       infinitely if no Content-Length header is provided.
     * Returns: The number of bytes that were read.
     */
    public ulong readBody(S)(ref S outputStream, bool allowInfiniteRead = false) if (isByteOutputStream!S) {
        const string* contentLengthStrPtr = "Content-Length" in headers;
        // If we're not allowed to read infinitely, and no content-length is given, don't attempt to read.
        if (!allowInfiniteRead && contentLengthStrPtr is null) {
            return 0;
        }
        Nullable!ulong contentLength;
        if (contentLengthStrPtr !is null) {
            import std.conv : to, ConvException;
            try {
                contentLength = nullable((*contentLengthStrPtr).to!ulong);
            } catch (ConvException e) {
                warnF!"Caught ConvException: %s; while parsing Content-Length header: %s"(e.msg, *contentLengthStrPtr);
                // Invalid formatting for content-length header.
                // If we don't allow infinite reading, quit 0.
                if (!allowInfiniteRead) {
                    return 0;
                }
            }
        }
        return this.readBody!(S)(outputStream, contentLength);
    }

    unittest {
        import std.conv;
        import handy_httpd.util.builders;

        // Test case 1: Simply reading a string.
        string body1 = "Hello world!";
        HttpRequest r1 = new HttpRequestBuilder().withBody(body1).build();
        auto sOut1 = byteArrayOutputStream();
        ulong bytesRead1 = r1.readBody(sOut1);
        assert(bytesRead1 == body1.length);
        assert(sOut1.toArrayRaw() == cast(ubyte[]) body1);

        // Test case 2: Missing Content-Length header, so we don't read anything.
        string body2 = "Goodbye, world.";
        HttpRequest r2 = new HttpRequestBuilder().withBody(body2).withoutHeader("Content-Length").build();
        auto sOut2 = byteArrayOutputStream();
        ulong bytesRead2 = r2.readBody(sOut2);
        assert(bytesRead2 == 0);
        assert(sOut2.toArrayRaw().length == 0);

        // Test case 3: Missing Content-Length header but we allow infinite reading.
        string body3 = "Hello moon!";
        HttpRequest r3 = new HttpRequestBuilder().withBody(body3).withoutHeader("Content-Length").build();
        auto sOut3 = byteArrayOutputStream();
        ulong bytesRead3 = r3.readBody(sOut3, true);
        assert(bytesRead3 == body3.length);
        assert(sOut3.toArrayRaw() == cast(ubyte[]) body3);
    }

    /** 
     * Internal helper function to read a body when we may or may not be
     * expecting a certain length.
     * Params:
     *   outputStream = The output stream to transfer to.
     *   expectedLength = The expected length.
     * Returns: The number of bytes read.
     */
    private ulong readBody(S)(
        ref S outputStream,
        Nullable!ulong expectedLength
    ) if (isByteOutputStream!S) {
        import std.algorithm : min;

        debugF!"Reading request body. Expected length: %s"(expectedLength);
        ulong bytesRead = 0;
        
        while (expectedLength.isNull || bytesRead < expectedLength.get()) {
            const uint bytesToRead = expectedLength.isNull
                ? cast(uint) this.receiveBuffer.length
                : min(expectedLength.get() - bytesRead, cast(uint)this.receiveBuffer.length);
            StreamResult readResult = this.inputStream.readFromStream(this.receiveBuffer[0 .. bytesToRead]);
            if (readResult.hasError) {
                throw new Exception("Stream read error: " ~ cast(string) readResult.error.message);
            }
            traceF!"Received %d bytes when attempting to read at least %d."(readResult.count, bytesToRead);
            if (readResult.count == 0) break;

            StreamResult writeResult = outputStream.writeToStream(this.receiveBuffer[0 .. readResult.count]);
            if (writeResult.hasError) {
                static if (isClosableStream!S) {
                    OptionalStreamError closeError = outputStream.closeStream();
                    if (closeError.present) {
                        errorF!"Failed to close output stream after write error: %s"(closeError.value.message);
                    }
                }
                throw new Exception("Stream write error: " ~ cast(string) writeResult.error.message);
            }
            if (writeResult.count != readResult.count) {
                throw new Exception("Couldn't write all bytes to output stream.");
            }
            bytesRead += writeResult.count;
        }

        debugF!"Reading completed. Expected length: %s, bytes read: %d"(expectedLength, bytesRead);
        return bytesRead;
    }

    /** 
     * Convenience method for reading the entire request body as an array of
     * bytes.
     * Params:
     *   allowInfiniteRead = Whether to read until no more data is available.
     * Returns: The byte content of the request body.
     */
    public ubyte[] readBodyAsBytes(bool allowInfiniteRead = false) {
        import streams.types.array;
        auto sOut = byteArrayOutputStream();
        readBody(sOut, allowInfiniteRead);
        return sOut.toArray();
    }

    /** 
     * Convenience method for reading the entire request body as a string.
     * Params:
     *   allowInfiniteRead = Whether to read until no more data is available.
     * Returns: The string contents of the request body.
     */
    public string readBodyAsString(bool allowInfiniteRead = false) {
        ubyte[] bytes = readBodyAsBytes(allowInfiniteRead);
        return cast(string) bytes;
    }

    /** 
     * Convenience method for reading the entire request body as a JSON node.
     * An exception will be thrown if the body cannot be parsed as JSON.
     * Params:
     *   allowInfiniteRead = Whether to read until no more data is available.
     * Returns: The request body as a JSON node.
     */
    public auto readBodyAsJson(bool allowInfiniteRead = false) {
        import std.json : parseJSON;
        return parseJSON(readBodyAsString(allowInfiniteRead));
    }

    /** 
     * Convenience method for reading the entire request body to a file.
     * Params:
     *   filename = The name of the file to write to.
     *   allowInfiniteRead = Whether to read until no more data is available.
     * Returns: The size of the received file, in bytes.
     */
    public ulong readBodyToFile(string filename, bool allowInfiniteRead = false) {
        import std.string : toStringz;
        auto sOut = FileOutputStream(toStringz(filename));
        ulong bytesRead = readBody(sOut, allowInfiniteRead);
        sOut.closeStream();
        return bytesRead;
    }
}

/** 
 * Enumeration of all possible HTTP request methods as unsigned integer values
 * for efficient logic.
 * 
 * https://developer.mozilla.org/en-US/docs/Web/HTTP/Methods
 */
public enum Method : ushort {
    GET     = 1 << 0,
    HEAD    = 1 << 1,
    POST    = 1 << 2,
    PUT     = 1 << 3,
    DELETE  = 1 << 4,
    CONNECT = 1 << 5,
    OPTIONS = 1 << 6,
    TRACE   = 1 << 7,
    PATCH   = 1 << 8
}

import std.traits : EnumMembers;

/** 
 * Constant that defines the number of available methods.
 */
public static const METHOD_COUNT = [EnumMembers!Method].length;

/** 
 * Gets the zero-based index of a method enum value, useful for histograms.
 * Params:
 *   method = The method to get the index for.
 * Returns: The index of the method.
 */
public size_t methodIndex(Method method) {
    static foreach (i, member; EnumMembers!Method) {
        if (method == member) return i;
    }
    assert(0, "Not an enum member.");
}

/** 
 * Gets a method using a zero-based index of the method enum value.
 * Params:
 *   idx = The index to find the method by.
 * Returns: The method at the given index.
 */
public Method methodFromIndex(size_t idx) {
    static foreach (i, member; EnumMembers!Method) {
        if (i == idx) return member;
    }
    return Method.GET;
}

/** 
 * Gets a Method enum value from a string. Defaults to GET for unknown names.
 * Params:
 *   name = The string representation of the method.
 * Returns: The method enum value.
 */
public Method methodFromName(string name) {
    import std.string : toUpper, strip;
    name = toUpper(strip(name));
    switch (name) {
        case "GET":
            return Method.GET;
        case "HEAD":
            return Method.HEAD;
        case "POST":
            return Method.POST;
        case "PUT":
            return Method.PUT;
        case "DELETE":
            return Method.DELETE;
        case "CONNECT":
            return Method.CONNECT;
        case "OPTIONS":
            return Method.OPTIONS;
        case "TRACE":
            return Method.TRACE;
        case "PATCH":
            return Method.PATCH;
        default:
            return Method.GET;
    }
}

/** 
 * Gets the string representation of a Method enum value.
 * Params:
 *   method = The method enum value.
 * Returns: The string representation.
 */
public string methodToName(const Method method) {
    final switch (method) {
        case Method.GET:
            return "GET";
        case Method.HEAD:
            return "HEAD";
        case Method.POST:
            return "POST";
        case Method.PUT:
            return "PUT";
        case Method.DELETE:
            return "DELETE";
        case Method.CONNECT:
            return "CONNECT";
        case Method.OPTIONS:
            return "OPTIONS";
        case Method.TRACE:
            return "TRACE";
        case Method.PATCH:
            return "PATCH";
    }
}

/** 
 * Builds a bitmask from the given list of method names.
 * Params:
 *   names = The method names to use.
 * Returns: A bitmask where bits are active for each method in the given list.
 */
public ushort methodMaskFromNames(string[] names) {
    ushort mask = 0;
    foreach (name; names) mask |= methodFromName(name);
    return mask;
}

unittest {
    assert(methodMaskFromNames([]) == 0);
    assert((methodMaskFromNames(["GET"]) & Method.GET) > 0);
    auto m1 = methodMaskFromNames(["GET", "POST", "PATCH"]);
    assert((m1 & Method.GET) > 0);
    assert((m1 & Method.POST) > 0);
    assert((m1 & Method.PATCH) > 0);
    assert((m1 & Method.CONNECT) == 0);
}

/** 
 * Gets a mask that contains every method.
 * Returns: The bit mask.
 */
public ushort methodMaskFromAll() {
    import std.traits : EnumMembers;
    ushort mask;
    static foreach (member; EnumMembers!Method) {
        mask |= member;
    }
    return mask;
}

/** 
 * Converts a method mask to a list of strings representing method names.
 * Params:
 *   mask = The mask to convert.
 * Returns: A list of method names.
 */
public string[] methodMaskToStrings(const ushort mask) {
    import std.traits : EnumMembers;
    string[] names;
    static foreach (member; EnumMembers!Method) {
        if ((mask & member) > 0) names ~= methodToName(member);
    }
    return names;
}

unittest {
    assert(methodMaskToStrings(0) == []);
    assert(methodMaskToStrings(methodMaskFromNames(["GET"])) == ["GET"]);
    assert(methodMaskToStrings(methodMaskFromNames(["GET", "PUT"])) == ["GET", "PUT"]);
    // The resulting list should always be in enum order.
    assert(methodMaskToStrings(methodMaskFromNames(["PUT", "POST"])) == ["POST", "PUT"]);
}
