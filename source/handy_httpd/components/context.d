/**
 * This module defines the "Request Context" concept, which is that, in
 * addition to the request and response, request handlers in Handy-http also
 * have access to a request context containing things like a reference to the
 * server, parsed path parameters, and other extras that are specific to this
 * web server.
 */
module handy_httpd.components.context;

import handy_httpd.server;
import http_primitives.util.multivalue_map;

/**
 * A static (separate instance per physical thread) request context that can be
 * accessed by request handlers to get extra information specific to this server.
 * Handy-http will set this up prior to calling your handler.
 */
static RequestContext REQUEST_CONTEXT;

/**
 * Extra data about a request that's available via the static `REQUEST_CONTEXT`
 * variable.
 */
struct RequestContext {
    HttpServer server;
    StringMultiValueMap pathParams;
}
