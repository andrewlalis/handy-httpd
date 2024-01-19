/**
 * This module defines functions and data structures for dealing with data in
 * the `application/x-www-form-urlencoded` format as defined here:
 * https://url.spec.whatwg.org/#application/x-www-form-urlencoded
 */
module handy_httpd.components.form_urlencoded;

import handy_httpd.components.multivalue_map;

private struct QueryParam {
    string name;
    string value;
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
StringMultiValueMap parseFormUrlEncoded(string queryString, bool stripWhitespace = true) {
    import std.array : array;
    import std.string : split;
    import std.algorithm : filter, map;

    if (queryString.length > 0 && queryString[0] == '?') {
        queryString = queryString[1..$];
    }

    auto params = queryString.split("&").filter!(s => s.length > 0)
        .map!(s => parseSingleQueryParam(s, stripWhitespace));
    StringMultiValueMap.Builder mapBuilder;
    foreach (QueryParam param; params) {
        mapBuilder.add(param.name, param.value);
    }
    return mapBuilder.build();
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
    import std.uri : decode;

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
    name = name.replace("+", " ").decode();
    value = value.replace("+", " ").decode();
    if (stripWhitespace) {
        name = name.strip();
        value = value.strip();
    }
    return QueryParam(name, value);
}

unittest {
    void doTest(string[][string] expectedResult, string queryString, bool stripWhitespace = true) {
        import std.format;
        auto actual = parseFormUrlEncoded(queryString, stripWhitespace);
        auto expected = StringMultiValueMap.fromAssociativeArray(expectedResult);
        assert(
            actual == expected,
            format!"Parsed query string %s resulted in %s instead of %s."(queryString, actual, expected)
        );
    }
    doTest(["a": ["1"], "b": ["2"]], "a=1&b=2");
    doTest(["a": ["1"], "b": ["2"]], "?a=1&b=2");
    doTest(["a": ["1"], "b": ["2"]], "  a =   1  &  b  =  2  ");
    doTest(["a": ["1"], "b": ["2"]], "  a =   1  &  b  =  2  ");
    doTest(["a": ["  1"]], "a=%20%201", false);
    doTest(["a": [""], "b": [""], "c": ["hello"]], "a&b&c=hello");
    doTest(["a": ["", "hello", "test"], "b": [""]], "a&a=hello&a=test&b");
}