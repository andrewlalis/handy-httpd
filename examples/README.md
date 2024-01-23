# Examples
Inside this directory, you'll find a series of examples which show how Handy-httpd can be used.

Single-file scripts annotated with a shebang can be run in a unix command-line with `./<script.d>`. On other systems, you should be able to do `dub run --single <script.d>`.

## Runner Script

A **runner** script is provided for your convenience. Compile it with `dmd runner.d`, or run directly with `./runner.d`. You can:
- List all examples: `./runner list`
- Clean the examples directory and remove compiled binaries: `./runner clean`
- Select an example to run from a list: `./runner run`
- Run a specific example: `./runner run <example>`
- Run all examples at the same time: `./runner run all`

> Note: When running all examples at the same time, servers will each be given a different port number, starting at 8080.
