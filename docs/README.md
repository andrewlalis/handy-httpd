# Handy-Httpd Documentation

The documentation for Handy-Httpd is built using [Vuepress](https://vuepress.vuejs.org/), so that we can write pages as markdown files, and it'll transform them into a pretty static bundle of HTML to serve.

## DDoc

To help improve the consistency of the documentation, we roll our own D-documentation via the `build-ddoc.d` script. It builds all documentation for Handy-Httpd, and places it into `docs/src/.vuepress/public/ddoc/`, so it can be served as static content along with the rest of the documentation site.

To link to a D symbol in a documentation markdown file, use the `ddoc-link` plugin by writing a specially-formatted link that starts with `ddoc-`, followed by the fully-qualified symbol name. In the example below, we create a link to the `PathHandler` class.

```markdown
Click on the [PathHandler](ddoc-handy_httpd.handlers.path_handler.PathHandler) link to learn more!
```

## Deployment

When commits are pushed to `main` that include changes from the `docs/` directory, a GitHub Action will run `npm run build` to build the static site, and then publish it at https://andrewlalis.github.io/handy-httpd/.
