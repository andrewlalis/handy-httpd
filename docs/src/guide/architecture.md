# Server Architecture

**⚠️ This page is a work-in-progress.**

This page will go into detail about the design of Handy-Httpd, both in terms of abstract concepts, and implementation details. It's usually not necessary to understand the contents of this page in order to effectively use Handy-Httpd, but it can help get the most out of your server, and will probably help if you'd like to contribute to this framework in any way.

## Project Structure

The Handy-Httpd project is organized into a main directories:

- `/source` contains all the source code for the project.
- `/examples` contains all the examples that are referenced anywhere throughout this documentation, and any others.
- `/integration-tests` contains all integration tests that involve their own unique testing setup.
- `/docs` contains this documentation site.
- `/design` contains any design documents.

The majority of this architecture document will cover the project's source code, as the other directories are fairly straightforward and self-explanatory.

Within `/source`, Handy-Httpd is divided into modules according to the principle of single-responsibility. Generally, every module in Handy-Httpd has one responsibility; it offers one key ingredient to the project.

### handy_httpd.server

The server module defines the main `HttpServer` class that acts as the foundation for the entire framework. The server runs a main loop that accepts new clients, and passes them off to a request handler.
