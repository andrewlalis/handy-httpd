# About Handy-Httpd

Handy-Httpd is a simple, easy-to-use and easy-to-read implementation of the classic thread-based HTTP server. It uses a pool of worker threads to handle incoming requests, and follows the HTTP/1.1 connection style, where we accept a new client socket, read its request, send a response, and then close the socket.

It's written using plain D, with the help of the [httparsed](https://code.dlang.org/packages/httparsed) library by Tomáš Chaloupka for parsing HTTP requests. While we don't shy away from using D's garbage collector, a lot of effort has been made to minimize the amount of allocations done at runtime, so we can benefit from a class-based approach, without the performance hit that usually incurs.

> As far as I (Andrew, the author of this library) am concerned, implementation of HTTP/2 or HTTP/3 is beyond the scope of my abilities, and would complicate this project unnecessarily. If you do need these features, and want to use Handy-Httpd too, don't fear! A common approach is to set up Nginx or some other high-performance server as a reverse proxy. It handles SSL, HTTP/2, load-balancing, and all the other fancy stuff that's already been figured out by people smarter than me.
