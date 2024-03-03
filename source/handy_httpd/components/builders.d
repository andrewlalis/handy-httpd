/**
 * Components used to build HTTP request information, mostly for convenience in
 * test cases.
 */
module handy_httpd.components.builders;

import std.range;
import http_primitives;

struct RequestResponsePair {
    HttpRequest request;
    HttpResponse response;
}

HttpRequest buildRequest(Method method, string url) {
    HttpRequest request;
    request.method = method;
    request.url = url;
    return request;
}

HttpResponse buildDiscardingResponse() {
    HttpResponse response;
    response.outputRange = cast(OutputRange!(ubyte[])) outputRangeObject(nullSink);
    return response;
}
