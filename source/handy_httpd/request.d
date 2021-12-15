module handy_httpd.request;

struct HttpRequest {
    public const string method;
    public const string url;
    public const string httpVersion;
    public const string[string] headers;
}
