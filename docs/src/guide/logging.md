# Logging

Handy-Httpd uses the [SLF4D](https://github.com/andrewlalis/slf4d) library for logging. That means that you can easily handle its log messages using a provider of your choice, or just let SLF4D's default logging provider send log messages to stdout and stderr. By default SLF4D's root logging level is `INFO`. If you'd like more detail about how Handy-Httpd operates, you can set the root level to `DEBUG` or `TRACE`.

To quickly enable colored, verbose logging in case your application isn't behaving how you expect, insert this snippet at the very beginning of your D application's `main` function:

```d
import slf4d;
import slf4d.default_provider;
auto provider = new shared DefaultProvider(true, Levels.TRACE);
configureLoggingProvider(provider);
```

This will configure the global SLF4D logging context to use the _default provider_, with colored output, and showing **all** log messages. You can use `Levels.DEBUG` if trace is too verbose for your needs.
