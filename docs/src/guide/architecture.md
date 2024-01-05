# Project Architecture

This page will go into detail about the design of Handy-Httpd, both in terms of abstract concepts, and implementation details. It's usually not necessary to understand the contents of this page in order to effectively use Handy-Httpd, but it can help get the most out of your server, and will probably help if you'd like to contribute to this framework in any way.

## Project Structure

The Handy-Httpd project is organized into a main directories:

- [`/source`](https://github.com/andrewlalis/handy-httpd/tree/main/source) contains all the source code for the project.
- [`/examples`](https://github.com/andrewlalis/handy-httpd/tree/main/examples) contains all the examples that are referenced anywhere throughout this documentation, and any others.
- [`/integration-tests`](https://github.com/andrewlalis/handy-httpd/tree/main/integration-tests) contains all integration tests that involve their own unique testing setup.
- [`/docs`](https://github.com/andrewlalis/handy-httpd/tree/main/docs) contains this documentation site.
- [`/design`](https://github.com/andrewlalis/handy-httpd/tree/main/design) contains any design documents.

The majority of this architecture document will cover the project's source code, as the other directories are fairly straightforward and self-explanatory.

Within `/source`, Handy-Httpd is divided into modules according to the principle of single-responsibility. Generally, every module in Handy-Httpd has one responsibility; it offers one key ingredient to the project.

### handy_httpd.server

The server module defines the main `HttpServer` class that acts as the foundation for the entire framework. The server runs a main loop that accepts new sockets (a client's connection), inserts them into an internal queue, and eventually a worker will become available to remove each socket and process it.

### handy_httpd.components

The components module contains everything directly required to run the server. Each module deals with one particular part of the complex topic of running an HTTP server.

Most modules are standalone, but for example, `handy_httpd.components.websocket` is comprised of several further modules (`frame`, `handler`, etc.) to aid in reducing the complexity of any one module.

Atop each module's declaration, you should find a description of that module's scope and purpose, so for the sake of sanity, each and every module will not be listed here.

### handy_httpd.handlers

The handlers module contains a collection of `HttpRequestHandler` implementations that come included with every Handy-Httpd installation, since they are quite useful in many common HTTP scenarios. Each handler defined here is also documented under **"Useful Handlers"** in this documentation site, and they're all sufficiently documented in the source code, so feel free to read about them in more detail, but we won't do so here.

### handy_httpd.util

The util module contains auxiliary utilities that aren't directly required to start the server, but might be useful to programmers in some circumstances, like testing helpers.

## Continuous Integration, Testing, and Deployment

This project uses GitHub's built-in *Actions* for its automated testing and deployment workflows. There are two primary workflows:

1. [`testing.yml`](https://github.com/andrewlalis/handy-httpd/blob/main/.github/workflows/testing.yml) is triggered on any push to the `main` branch which includes changes to the project's source code, examples, or integration tests. It runs the project's unit tests and integration tests on a variety of operating systems and compiler flavors to ensure that Handy-Httpd will work on a wide variety of devices.
<br>
**Note:** Pull requests will not be merged unless the testing workflow passes on the latest commit. No exceptions will be made!

2. [`deploy-docs.yml`](https://github.com/andrewlalis/handy-httpd/blob/main/.github/workflows/deploy-docs.yml) is triggered on any push to the `main` branch which includes changes to the project's source code, examples, integration  tests, or documentation source. It builds a static HTML site from this documentation's markdown and Vuepress configuration, and deploys it to GitHub pages.

### Deploying a New Version

Because this project is available on [dub](https://code.dlang.org/), there's no need to compile and publish any library artifacts. All that must be done is to add a tag to the latest commit on the repository's `main` branch, and push that to the origin.
