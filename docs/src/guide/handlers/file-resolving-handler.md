# File Resolving Handler

If you just want to serve plain files from directory, look no further than the [FileResolvingHandler](ddoc-handy_httpd.handlers.file_resolving_handler._File_Resolving_Handler). It is a pre-made request handler that you can use in your server to serve files for a specified directory.

In the example below, we create a new FileResolvingHandler that will serve content from a `static-content` directory, relative to where the program's working directory.

```d
auto fileHandler = new FileResolvingHandler("static-content");
new HttpServer(fileHandler).start();
```

## Directory Resolution Strategies

There are a few different ways that the FileResolvingHandler can deal with requests to directories:

1. Try to find an "index" file and serve that (like `index.html`, `index.txt`, etc).
2. Show a listing of all entries in the directory.
3. Return a 404 Not Found response.

You can configure the strategy that's used via the `directoryResolutionStrategy` constructor argument. It defaults to `listDirContentsAndServeIndexFiles`, but can be set via any of the following strategies defined in [DirectoryResolutionStrategies](ddoc-handy_httpd.handlers.file_resolving_handler.DirectoryResolutionStrategies):

| Strategy | Effect |
|---       |---     |
| `listDirContentsAndServeIndexFiles` | Tries to serve index files, and if none are found, shows a directory listing. |
| `listDirContents` | Shows a directory listing. |
| `serveIndexFiles` | Tries to serve index files, or 404 if none are found. |
| `none` | Always return a 404. |

Here's an example where we configure a handler to serve index files, but _not_ show a directory listing:

```d
auto fileHandler = new FileResolvingHandler(
    "static-content",
    DirectoryResolutionStrategies.serveIndexFiles
);
new HttpServer(fileHandler).start();
```
