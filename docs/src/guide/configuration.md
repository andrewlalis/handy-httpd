# Configuration

Handy-Httpd servers are highly-configurable thanks to a simple [ServerConfig](ddoc-handy_httpd.components.config.ServerConfig) struct that's passed to the server on initialization. On this page, we'll cover all of the available configuration options, what they mean, and how changing them can affect your server.

> Note: Configuration options **cannot** be changed during runtime.

## Socket Options

The following options pertain to how the server's internal socket is initialized.

### `hostname`
| Type | Default Value |
|---   |---            |
| `string` | `"127.0.0.1"` |
The hostname that the server socket will bind to.

### `port`
| Type | Default Value |
|---   |---            |
| `ushort` | `8080` |
The port that the server socket will bind to.

### `reuseAddress`
| Type | Default Value |
|---   |---            |
| `bool` | `true` |
Whether to set the `REUSEADDR` socket option, which allows for a socket to be quickly reused after it's closed.

### `connectionQueueSize`
| Type | Default Value |
|---   |---            |
| `int` | `100` |
The number of connections that will be queued by the server socket as it processes new sockets through its `accept()` method.

### `preBindCallbacks`
| Type | Default Value |
|---   |---            |
| [SocketConfigurationFunction[]](ddoc-handy_httpd.components.config.ServerConfig.SocketConfigureFunction) | `[]` |
A list of `void delegate(Socket)` functions that are called on the server socket before it's bound to the configured address. These functions can be used to set any additional options which aren't exposed by this configuration struct.

### `receiveBufferSize`
| Type | Default Value |
|---   |---            |
| `size_t` | `8192` |
The size of the pre-allocated receive buffer that each worker thread uses when reading incoming requests from sockets. Making this larger will use a larger amount of memory, but may improve performance for requests will large headers and body content.

## Http Options

 These options can be used to configure the server's HTTP-specific behavior.

 ### `defaultHeaders`
| Type | Default Value |
|---   |---            |
| `string[string]` | `string[string].init` (empty associative array) |
An associative array of headers that will be added to every response the server sends back to clients. These headers are added before the handler receives the request context.

## Server Options

These options can be used to configure the general server behavior.

### `workerPoolSize`
| Type | Default Value |
|---   |---            |
| `size_t` | `25` |
The number of worker threads to use to process incoming requests. Increasing this number can improve performance for servers where the bottleneck is in the number of concurrent requests.

### `workerPoolManagerIntervalMs`
| Type | Default Value |
|---   |---            |
| `uint` | `10_000` (10 seconds) |
The number of milliseconds that the worker pool manager should wait between each health check it performs. Each health check can find and replace worker threads that have died due to an uncaught error or exception.

This interval shouldn't need to be very small, unless a high percentage of your requests end up killing their worker thread with a fatal error.

### `enableWebSockets`
| Type | Default Value |
|---   |---            |
| `bool` | `true` |
Whether to enable websocket functionality for the server. If set to true, starting the server will also start an additional thread that handles websocket traffic in a nonblocking fashion.
