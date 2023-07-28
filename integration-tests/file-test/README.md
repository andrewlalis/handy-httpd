# File Integration Tests

This suite of integration tests runs some checks to ensure that operations with
larger files (uploading/downloading) work as expected, since this is something
that can often lead to bugs that only pop up once you start working with real
data.

This integration test is orchestrated by an external Java program found in `Tests.java`. To run the tests, simply run `java Tests.java` with JVM 17 or higher.
