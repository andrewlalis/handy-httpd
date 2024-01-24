# Examples
Inside this directory, you'll find a series of examples which show how Handy-httpd can be used.

Single-file scripts annotated with a shebang can be run in a unix command-line with `./<script.d>`. On other systems, you should be able to do `dub run --single <script.d>`.

| Example | Description |
|---|---|
| hello-world | Basic example which shows how to configure and start a server. |
| using-headers | Shows you how to inspect, list, and get the headers from a request. |
| path-handler | Shows you how to use the `PathHandler` to route requests to handlers based on their path, and consume path variables from the request's URL. |
| file-upload | Demonstrates file uploads using multipart/form-data encoding. |
| handler-testing | Shows how you can write unit tests for your request handler functions or classes. |
| static-content-server | Shows how you can use the `FileResolvingHandler` to serve static files from a directory. |
| websocket | Shows how you can enable websocket support and use the `WebSocketHandler` to send and receive websocket messages. |


## Runner Script

A runner script is provided for your convenience. Compile it with `dmd runner.d`, or run directly with `./runner.d`. You can:
- List all examples: `./runner list`
- Clean the examples directory and remove compiled binaries: `./runner clean`
- Select an example to run from a list: `./runner run`
- Run a specific example: `./runner run <example>`
- Run all examples at the same time: `./runner run all`

> Note: When running all examples at the same time, servers will each be given a different port number, starting at 8080.
