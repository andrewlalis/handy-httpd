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
import handy_httpd.components.parse_utils;
import streams;

/** 
 * Builds a request context with a request with the given information, and a
 * plain response that's ready to be written to.
 * Params:
 *   method = The request method.
 *   url = The requested URL.
 *   bodyContent = The body of the request. This can be null.
 *   contentType = The type of the body. This can be null.
 * Returns: A request context.
 */
public HttpRequestContext buildCtxForRequest(
    Method method,
    string url,
    string bodyContent,
    string contentType = "text/plain"
) {
    auto urlAndParams = parseUrlAndParams(url);
    return new HttpRequestContextBuilder()
        .withRequest((rb) {
            rb.withMethod(method)
                .withUrl(urlAndParams[0])
                .withParams(urlAndParams[1]);
            if (bodyContent !is null && contentType !is null) {
                rb.withBody(bodyContent, contentType);
            }
        })
        .build();
}

/** 
 * Builds a request context with a request with the given information, and a
 * plain response that's ready to be written to.
 * Params:
 *   method = The request method.
 *   url = The requested URL.
 * Returns: A request context.
 */
public HttpRequestContext buildCtxForRequest(Method method, string url) {
    return buildCtxForRequest(method, url, null, null);
}

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

    /** 
     * Modifies this builder's request with the given delegate.
     * Params:
     *   dg = The delegate function to apply to the request builder.
     * Returns: A reference to this builder.
     */
    public HttpRequestContextBuilder withRequest(void delegate(HttpRequestBuilder) dg) {
        dg(this.requestBuilder);
        return this;
    }

    /** 
     * Modifies this builder's response with the given delegate.
     * Params:
     *   dg = The delegate function to apply to the response builder.
     * Returns: A reference to this builder.
     */
    public HttpRequestContextBuilder withResponse(void delegate(HttpResponseBuilder) dg) {
        dg(this.responseBuilder);
        return this;
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
    private InputStream!ubyte inputStream = null;

    this() {
        this.method = Method.GET;
        this.url = "/";
    }

    this(string method, string url) {
        this.method = methodFromName(method);
        this.url = url;
    }

    HttpRequestBuilder withMethod(Method method) {
        this.method = method;
        return this;
    }

    HttpRequestBuilder withMethod(string method) {
        return this.withMethod(methodFromName(method));
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

    HttpRequestBuilder withoutHeader(string name) {
        this.headers.remove(name);
        return this;
    }

    HttpRequestBuilder withParams(string[string] params) {
        this.params = params;
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

    HttpRequestBuilder withInputStream(InputStream!ubyte inputStream) {
        this.inputStream = inputStream;
        return this;
    }

    HttpRequestBuilder withBody(ubyte[] bodyContent, string contentType = "application/octet-stream") {
        return this.withInputStream(inputStreamObjectFor(arrayInputStreamFor(bodyContent)))
        .withHeader("Content-Type", contentType)
        .withHeader("Content-Length", bodyContent.length);
    }

    HttpRequestBuilder withBody(string bodyContent, string contentType = "text/plain") {
        return this.withBody(cast(ubyte[]) bodyContent, contentType);
    }

    HttpRequest build() {
        return HttpRequest(
            this.method,
            this.url,
            1,
            this.headers,
            this.params,
            this.pathParams,
            this.inputStream,
            new ubyte[8192]
        );
    }
}

class HttpResponseBuilder {
    private StatusInfo status = HttpStatus.OK;
    private string[string] headers;
    private OutputStream!ubyte outputStream = outputStreamObjectFor(NoOpOutputStream!ubyte());

    HttpResponseBuilder withStatus(StatusInfo status) {
        this.status = status;
        return this;
    }

    HttpResponseBuilder withHeader(string name, string value) {
        this.headers[name] = value;
        return this;
    }

    HttpResponseBuilder withHeader(V)(string name, V value) {
        import std.conv : to;
        this.headers[name] = value.to!string;
        return this;
    }

    HttpResponseBuilder withoutHeader(string name) {
        this.headers.remove(name);
        return this;
    }

    HttpResponseBuilder withOutputStream(OutputStream!ubyte outputStream) {
        this.outputStream = outputStream;
        return this;
    }

    // HttpResponseBuilder withBody(ubyte[] bodyContent, string contentType = "application/octet-stream") {
    //     return this.withOutputStream(outputStreamObjectFor())
    //     .withHeader("Content-Type", contentType)
    //     .withHeader("Content-Length", bodyContent.length);
    // }

    // HttpResponseBuilder withBody(string bodyContent, string contentType = "text/plain") {
    //     return this.withBody(cast(ubyte[]) bodyContent, contentType);
    // }

    HttpResponse build() {
        return HttpResponse(
            status,
            headers,
            false,
            outputStream
        );
    }
}