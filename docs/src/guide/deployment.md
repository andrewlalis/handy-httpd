# Deployment Tips

Now that you've gone and done the hard work of making your very own HTTP server, it's time to go and share it with the world.

This page contains a list of tips that should help you get the most out of your server when it's deployed somewhere.

1. Use [LDC](https://github.com/ldc-developers/ldc) to compile the release version of your application. Compile times with LDC are a little longer than with DMD, but you get much better performance, and better compatibility with various OS/arch combinations because the project is based on LLVM.
2. Tune the number of worker threads according to your needs. For small services, you can usually get by with just a few workers, and reducing the number of worker threads greatly cuts down on the memory usage of your application. See the [configuration page](configuration.md#workerpoolsize) for more details.
3. Use a [reverse-proxy](https://en.wikipedia.org/wiki/Reverse_proxy) like [nginx](https://www.nginx.com/) to send traffic to Handy-Httpd, instead of having Handy-Httpd handle traffic directly. This is because something like nginx is highly-optimized for maximum performance, and already handles encryption (HTTPS via SSL/TLS). This way, you (and me, the developer of Handy-Httpd) can focus on the features that improve the quality of the application, instead of worrying about problems others have solved. Also, consider serving static content via reverse-proxy for best performance.
4. Set [enableWebSockets](configuration.md#enablewebsockets) to `false` to save some memory. If websockets are enabled, an extra thread is started to manage the websocket messages, separate from the main worker pool. If you don't need websockets and you want to optimize your memory usage, disable them.
5. Avoid long-duration operations while handling requests. This locks up a worker thread for the duration of the request, so it's best to respond right away (also for the user's experience) and then do additonal processing asynchronously.
6. Try to avoid throwing exceptions from your request handlers, where possible. Handle exceptions as soon as they crop up, and set the appropriate HTTP response code instead of relying on Handy-Httpd's exception handling. Exceptions are quite costly in terms of performance.
