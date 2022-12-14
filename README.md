# handy-httpd

An extremely lightweight HTTP server for the [D programming language](https://dlang.org/).

## Start Your Server
In this example, we take advantage of the [Dub package manager](https://code.dlang.org/)'s single-file SDL syntax to declare HandyHttpd as a dependency. For this example, we'll call this `my_server.d`.
```d
#!/usr/bin/env dub
/+ dub.sdl:
	dependency "handy_httpd" version="~>3.4"
+/
import handy_httpd;

void main() {
	new HttpServer((ref ctx) {
		if (ctx.request.url == "/hello") {
			response.writeBody("Hello world!");
		} else {
			response.notFound();
		}
	}).start();
}
```
To start the server, just mark the script as executable, and run it:
```shell
chmod +x my_server.d
./my_server.d
```
And finally, if you navigate to http://localhost:8080/hello, you should see the `Hello world!` text appear.


