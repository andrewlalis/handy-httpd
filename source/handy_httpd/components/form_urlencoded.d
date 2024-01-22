/**
 * This module defines functions and data structures for dealing with data in
 * the `application/x-www-form-urlencoded` format as defined here:
 * https://url.spec.whatwg.org/#application/x-www-form-urlencoded
 */
module handy_httpd.components.form_urlencoded;

/**
 * Struct containing a single key-value pair that's obtained from parsing a
 * URL's query or form-urlencoded data.
 */
struct QueryParam {
    /// The name and value of this parameter.
    string name, value;

    /**
     * Converts a list of query params to an associative string array. This is
     * mainly meant as a holdover due to older code handling query params as
     * such an associative array. Note that the params are traversed in order,
     * so a parameter with the same name as a previous parameter will overwrite
     * its value.
     * Params:
     *   params = The ordered list of query params to convert.
     * Returns: The associative array.
     */
    static string[string] toMap(in QueryParam[] params) {
        string[string] m;
        foreach (QueryParam param; params) {
            m[param.name] = param.value;
        }
        return m;
    }

    /**
     * Converts an associative string array into a list of query params.
     * Params:
     *   m = The associative array of strings to convert.
     * Returns: The list of query params.
     */
    static QueryParam[] fromMap(in string[string] m) {
        QueryParam[] params;
        foreach (name, value; m) {
            params ~= QueryParam(name, value);
        }
        return params;
    }
}

/**
 * Parses a set of query parameters from a query string. This implementation
 * follows exactly the specification for parsing application/x-www-form-urlencoded
 * data as per the URL specification found here: https://url.spec.whatwg.org/#urlencoded-parsing
 * Params:
 *   queryString = The raw query string to parse, which may or may not contain
 *                 a preceding '?'.
 *   stripWhitespace = Whether to strip preceding and trailing whitespace from
 *                     parsed values. Note that this is not a part of the spec,
 *                     but added as a convenience.
 * Returns: A list of parsed key-value pairs.
 */
QueryParam[] parseFormUrlEncoded(string queryString, bool stripWhitespace = true) {
    import std.array : array;
    import std.string : split;
    import std.algorithm : filter, map;

    if (queryString.length > 0 && queryString[0] == '?') {
        queryString = queryString[1..$];
    }

    return queryString.split("&").filter!(s => s.length > 0)
        .map!(s => parseSingleQueryParam(s, stripWhitespace))
        .array;
}

/**
 * Internal function for parsing a single key-value pair from form-urlencoded
 * data.
 * Params:
 *   s = The string containing the query param to parse.
 *   stripWhitespace = Whether to strip whitespace from the param's name and value.
 * Returns: The query param that was parsed.
 */
private QueryParam parseSingleQueryParam(string s, bool stripWhitespace) {
    import std.string : strip, indexOf, replace;
    import std.uri : decodeComponent;

    string name, value;
    ptrdiff_t idx = s.indexOf('=');
    if (idx == -1) {
        // No '=' present, only include the param name and empty string value.
        name = s;
        value = "";
    } else if (idx == 0) {
        // '=' is the first character, so empty name.
        name = "";
        value = s;
    } else {
        // There is a name and value.
        name = s[0..idx];
        value = s[idx + 1 .. $];
    }

    // Replace 0x2B ('+') with 0x20 (' ').
    name = name.replace("+", " ").decodeComponent();
    value = value.replace("+", " ").decodeComponent();
    if (stripWhitespace) {
        name = name.strip();
        value = value.strip();
    }
    return QueryParam(name, value);
}

unittest {
    void doTest(QueryParam[] expectedResult, string queryString, bool stripWhitespace = true) {
        import std.format;
        auto actual = parseFormUrlEncoded(queryString, stripWhitespace);
        assert(
            actual == expectedResult,
            format!"Parsed query string resulted in %s instead of %s."(actual, expectedResult)
        );
    }
    doTest([QueryParam("a", "1"), QueryParam("b", "2")], "a=1&b=2");
    doTest([QueryParam("a", "1"), QueryParam("b", "2")], "?a=1&b=2");
    doTest([QueryParam("a", "1"), QueryParam("b", "2")], "  a =   1  &  b  =  2  ");
    doTest([QueryParam("a", "1"), QueryParam("b", "2")], "  a =   1  &  b  =  2  ");
    doTest([QueryParam("a", "  1")], "a=%20%201", false);
    doTest([QueryParam("a", ""), QueryParam("b", ""), QueryParam("c", "hello")], "a&b&c=hello");
    doTest(
        [QueryParam("a", ""), QueryParam("a", "hello"), QueryParam("a", "test"), QueryParam("b", "")],
        "a&a=hello&a=test&b"
    );
}
