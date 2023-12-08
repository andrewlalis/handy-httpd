# Introduction

Handy-Httpd is a simple, fast, extensible HTTP server that can be embedded in your [D lang](https://dlang.org/) applications. While there are more complex, fully-featured servers out there like [Vibe.d](https://vibed.org), Handy-Httpd tries to offer a simple solution for when you _just need a server_, and you just want to start right away.

To get started, add the latest version of Handy-Httpd to your Dub project.

```shell
dub add handy-httpd
```

Then, you can create a server like so:

```d
import handy_httpd;

void main() {
    auto server = new HttpServer((ref ctx) {
        ctx.response.writeBodyString("Hello world!");
    });
    server.start();
}
```

TIf you open your browser to [http://localhost:8080](http://localhost:8080), you should see the text, "Hello world!". The full example is available [on GitHub](https://github.com/andrewlalis/handy-httpd/tree/main/examples/single-file-server).


