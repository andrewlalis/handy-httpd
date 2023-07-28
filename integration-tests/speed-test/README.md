# Speed Integration Tests

This suite of integration tests includes some simple performance metrics to
see how many requests can be handled per second.

It's definitely not an authoritative metric that should be relied upon for
much, but it is used to see at a glance if the server is stable when serving
many thousands of requests per second.

Run it with `dub run`.
