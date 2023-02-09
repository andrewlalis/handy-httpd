module handy_httpd.utils;

import handy_httpd.server;
import handy_httpd.components.worker;
import handy_httpd.components.handler;
import handy_httpd.components.request;
import handy_httpd.components.response;
import std.socket;
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
    private Socket socket;

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

    public HttpRequestContextBuilder withSocket(Socket socket) {
        this.socket = socket;
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
        if (this.socket !is null) {
            this.requestBuilder.withSocket(this.socket);
            this.responseBuilder.withSocket(this.socket);
        }
        return HttpRequestContext(
            this.requestBuilder.build(),
            this.responseBuilder.build(),
            this.socket,
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
    private string method;
    private string url;
    private string[string] headers;
    private string[string] params;
    private string[string] pathParams;
    private Socket socket;

    this() {
        this.method = "GET";
        this.url = "/";
    }

    this(string method, string url) {
        this.method = method;
        this.url = url;
    }

    HttpRequestBuilder withHeader(string name, string value) {
        this.headers[name] = value;
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

    HttpRequestBuilder withSocket(Socket socket) {
        this.socket = socket;
        return this;
    }

    HttpRequest build() {
        return HttpRequest(
            this.method,
            this.url,
            1,
            this.headers,
            this.params,
            this.pathParams,
            this.socket
        );
    }
}

class HttpResponseBuilder {
    private ushort status = 200;
    private string statusText = "OK";
    private string[string] headers;
    private Socket socket;

    HttpResponseBuilder withStatus(ushort code, string text = "") {
        this.status = code;
        this.statusText = text;
        return this;
    }

    HttpResponseBuilder withHeader(string name, string value) {
        this.headers[name] = value;
        return this;
    }

    HttpResponseBuilder withSocket(Socket socket) {
        this.socket = socket;
        return this;
    }

    HttpResponse build() {
        return HttpResponse(
            status,
            statusText,
            headers,
            socket,
            false
        );
    }
}
