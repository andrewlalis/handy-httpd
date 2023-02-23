# Logging

Handy-Httpd uses the [SLF4D](https://github.com/andrewlalis/slf4d) library for logging. That means that you can easily handle its log messages using a provider of your choice, or just let SLF4D's default logging provider send log messages to stdout and stderr. By default SLF4D's root logging level is `INFO`. If you'd like more detail about how Handy-Httpd operates, you can set the root level to `DEBUG` or `TRACE`.
