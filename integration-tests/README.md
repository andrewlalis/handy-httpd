# Integration Tests

Handy-Httpd's integration tests are all independent programs that generally
declare the local handy-httpd source as a dependency using a relative path to
the repository's root directory.

The nature of each test may vary, but they generally start a server and run
some tests on it to ensure that it meets certain expectations, and the program
will fail with a non-zero exit code otherwise.

For systems with bash, you can use `run-all.sh` to run all integration tests,
one at a time.
