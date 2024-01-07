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
import handy_httpd.components.form_urlencoded;
import streams;
import std.socket : Address;

/** 
 * Builds a request context with a request with the given information, and a
 * plain response that's ready to be written to.
 * Params:
 *   method = The request method.
 *   url = The requested URL, which may include parameters.
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
        this.requestBuilder = new HttpRequestBuilder(this);
        this.responseBuilder = new HttpResponseBuilder(this);
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
     * Gets a reference to the request builder that will be used to create the
     * context's request. Call `and()` after you're done using it to continue
     * configuring the context.
     * Returns: A reference to the request builder.
     */
    public HttpRequestBuilder request() {
        return this.requestBuilder;
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

    /**
     * Gets a reference to the response builder that will be used to create the
     * context's response. Call `and()` after you're done using it to continue
     * configuring the context.
     * Returns: A reference to the response builder.
     */
    public HttpResponseBuilder response() {
        return this.responseBuilder;
    }

    /**
     * Configures the HTTP server that'll be used for this context.
     * Params:
     *   server = The server to use.
     * Returns: The context builder, for method chaining.
     */
    public HttpRequestContextBuilder withServer(HttpServer server) {
        this.server = server;
        return this;
    }

    /**
     * Configures the worker thread for this context.
     * Params:
     *   worker = The worker thread to use.
     * Returns: The context builder, for method chaining.
     */
    public HttpRequestContextBuilder withWorker(ServerWorkerThread worker) {
        this.worker = worker;
        return this;
    }

    /**
     * Builds the request context.
     * Returns: The HttpRequestContext.
     */
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
    private HttpRequestContextBuilder ctxBuilder;

    private Method method = Method.GET;
    private string url = "/";
    private string[string] headers;
    private QueryParam[] params;
    private string[string] pathParams;
    private string pathPattern = null;
    private InputStream!ubyte inputStream = null;
    private Address remoteAddress = null;

    this() {}

    this(string method, string url) {
        this.method = methodFromName(method);
        this.url = url;
    }

    this(HttpRequestContextBuilder ctxBuilder) {
        this.ctxBuilder = ctxBuilder;
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

    HttpRequestBuilder withParams(string paramsStr) {
        this.params = parseFormUrlEncoded(paramsStr);
        return this;
    }

    HttpRequestBuilder withParams(string[string] params) {
        this.params = QueryParam.fromMap(params);
        return this;
    }

    HttpRequestBuilder withParams(QueryParam[] params) {
        this.params = params;
        return this;
    }

    HttpRequestBuilder withParam(string name, string value) {
        this.params ~= QueryParam(name, value);
        return this;
    }

    HttpRequestBuilder withPathParam(string name, string value) {
        this.pathParams[name] = value;
        return this;
    }

    HttpRequestBuilder withPathPattern(string pathPattern) {
        this.pathPattern = pathPattern;
        return this;
    }

    HttpRequestBuilder withInputStream(S)(S inputStream) if (isByteInputStream!S) {
        this.inputStream = inputStreamObjectFor(inputStream);
        return this;
    }

    HttpRequestBuilder withInputStream(S)(
        S inputStream,
        ulong contentLength,
        string contentType = "application/octet-stream"
    ) if (isByteInputStream!S) {
        return this.withInputStream(inputStream)
            .withHeader("Content-Type", contentType)
            .withHeader("Content-Length", contentLength);
    }

    HttpRequestBuilder withBody(ubyte[] bodyContent, string contentType = "application/octet-stream") {
        return this.withInputStream(arrayInputStreamFor(bodyContent), bodyContent.length, contentType);
    }

    HttpRequestBuilder withBody(string bodyContent, string contentType = "text/plain") {
        return this.withBody(cast(ubyte[]) bodyContent, contentType);
    }

    HttpRequestBuilder withRemoteAddress(Address address) {
        this.remoteAddress = address;
        return this;
    }

    HttpRequest build() {
        return HttpRequest(
            this.method,
            this.url,
            1,
            this.headers,
            QueryParam.toMap(this.params),
            this.params,
            this.pathParams,
            this.pathPattern,
            this.inputStream,
            new ubyte[8192],
            this.remoteAddress
        );
    }

    /**
     * Fluent method to return to the request context builder. This is only
     * available if this builder is part of an HttpRequestContextBuilder.
     * Returns: A reference to the context builder that this response builder
     * belongs to.
     */
    HttpRequestContextBuilder and() {
        return this.ctxBuilder;
    }
}

/**
 * A utility class that provides a fluent interface for building HttpResponse
 * structs, mostly useful for testing.
 */
class HttpResponseBuilder {
    private HttpRequestContextBuilder ctxBuilder;

    private StatusInfo status = HttpStatus.OK;
    private string[string] headers;
    private OutputStream!ubyte outputStream = new ResponseCachingOutputStream();

    this() {}

    this(HttpRequestContextBuilder ctxBuilder) {
        this.ctxBuilder = ctxBuilder;
    }

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

    HttpResponse build() {
        return HttpResponse(
            status,
            headers,
            false,
            outputStream
        );
    }

    /**
     * Fluent method to return to the request context builder. This is only
     * available if this builder is part of an HttpRequestContextBuilder.
     * Returns: A reference to the context builder that this request builder
     * belongs to.
     */
    HttpRequestContextBuilder and() {
        return this.ctxBuilder;
    }
}

/**
 * A byte output stream implementation that caches HTTP header and body content
 * as it's written, so that you can fetch and inspect the contents later. This
 * is mainly intended as a helper for unit tests that involve checking the raw
 * response body for request handlers.
 *
 * To use this, create an instance and supply it to an HttpResponseBuilder when
 * building a mocked request context:
 * ```d
 * auto sOut = new ResponseCachingOutputStream();
 * auto ctx = new HttpRequestContextBuilder()
 *   .request().withMethod(Method.GET).withUrl("/users").and()
 *   .response().withOutputStream(sOut).and()
 *   .build();
 * myHandlerFunction(ctx);
 * assert(sOut.getBody() == "expected body content");
 * ```
 */
class ResponseCachingOutputStream : OutputStream!ubyte {
    import std.array;

    private Appender!string headerApp;
    private Appender!string bodyApp;
    private bool readingHeader = true;

    StreamResult writeToStream(ubyte[] buffer) {
        uint bufferIdx = 0;
        while (readingHeader) {
            headerApp ~= cast(char) buffer[bufferIdx++];
            if (headerApp.data.length > 3) {
                string suffix = headerApp.data[$ - 4 .. $];
                if (suffix == "\r\n\r\n") {
                    readingHeader = false;
                }
            }
        }
        bodyApp ~= buffer[bufferIdx .. $];
        return StreamResult(cast(uint) buffer.length);
    }

    string getHeader() {
        return headerApp[];
    }

    string getBody() {
        return bodyApp[];
    }
}
///
unittest {
    void mockHandler(ref HttpRequestContext ctx) {
        ctx.response.writeBodyString("Hello world!");
    }

    ResponseCachingOutputStream stream = new ResponseCachingOutputStream();
    HttpRequestContext ctx = new HttpRequestContextBuilder()
        .response()
            .withOutputStream(stream)
            .and()
        .build();
    mockHandler(ctx);
    assert(stream.getBody() == "Hello world!", stream.getBody());
}
