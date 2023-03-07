/** 
 * This module contains builder classes for a variety of components. These
 * builders are not intended for performance uses; mostly testing.
 */
module handy_httpd.util.builders;

import handy_httpd.server;
import handy_httpd.components.worker;
import handy_httpd.components.handler;
import handy_httpd.components.request;
import handy_httpd.components.response;
import handy_httpd.util.range;
import std.range;


/** 
 * A fluent-style builder for helping to create request contexts for unit
 * testing of any `HttpRequestHandler`, `HttpRequestFilter`, `ServerExceptionHandler`,
 * or any other components related to Handy-Httpd.
 */
class HttpRequestContextBuilder {
    private HttpRequestBuilder requestBuilder;
    private HttpResponseBuilder responseBuilder;
    private HttpServer server;
    private ServerWorkerThread worker;

    this() {
        this.requestBuilder = new HttpRequestBuilder();
        this.responseBuilder = new HttpResponseBuilder();
    }

    public HttpRequestBuilder request() {
        return this.requestBuilder;
    }

    public HttpResponseBuilder response() {
        return this.responseBuilder;
    }

    public HttpRequestContextBuilder withServer(HttpServer server) {
        this.server = server;
        return this;
    }

    public HttpRequestContextBuilder withWorker(ServerWorkerThread worker) {
        this.worker = worker;
        return this;
    }

    public HttpRequestContext build() {
        return HttpRequestContext(
            this.requestBuilder.build(),
            this.responseBuilder.build(),
            this.server,
            this.worker
        );
    }
}

/** 
 * A utility class for a fluent interface for building requests. This is useful
 * for testing.
 */
class HttpRequestBuilder {
    private Method method;
    private string url;
    private string[string] headers;
    private string[string] params;
    private string[string] pathParams;
    private InputRange!(ubyte[]) inputRange = new EmptyInputRange();

    this() {
        this.method = Method.GET;
        this.url = "/";
    }

    this(string method, string url) {
        this.method = methodFromName(method);
        this.url = url;
    }

    HttpRequestBuilder withMethod(string method) {
        this.method = methodFromName(method);
        return this;
    }

    HttpRequestBuilder withUrl(string url) {
        this.url = url;
        return this;
    }

    HttpRequestBuilder withHeader(string name, string value) {
        this.headers[name] = value;
        return this;
    }

    HttpRequestBuilder withHeader(V)(string name, V value) {
        import std.conv : to;
        this.headers[name] = value.to!string;
        return this;
    }

    HttpRequestBuilder withParam(string name, string value) {
        this.params[name] = value;
        return this;
    }

    HttpRequestBuilder withPathParam(string name, string value) {
        this.pathParams[name] = value;
        return this;
    }

    HttpRequestBuilder withInputRange(InputRange!(ubyte[]) inputRange) {
        this.inputRange = inputRange;
        return this;
    }

    HttpRequestBuilder withInputRange(string input) {
        return this.withInputRange(inputRangeObject([cast(ubyte[]) input.dup]));
    }

    HttpRequest build() {
        return HttpRequest(
            this.method,
            this.url,
            1,
            this.headers,
            this.params,
            this.pathParams,
            this.inputRange
        );
    }
}

class HttpResponseBuilder {
    private ushort status = 200;
    private string statusText = "OK";
    private string[string] headers;
    private OutputRange!(ubyte[]) outputRange = new DiscardingOutputRange();

    HttpResponseBuilder withStatus(ushort code, string text = "") {
        this.status = code;
        this.statusText = text;
        return this;
    }

    HttpResponseBuilder withHeader(string name, string value) {
        this.headers[name] = value;
        return this;
    }

    HttpResponseBuilder withOutputRange(OutputRange!(ubyte[]) outputRange) {
        this.outputRange = outputRange;
        return this;
    }

    HttpResponse build() {
        return HttpResponse(
            status,
            statusText,
            headers,
            false,
            outputRange
        );
    }
}