/**
 * This module contains a handler that applies filters to a request context
 * before (or after) handing it off to the proper handler.
 */
module handy_httpd.handlers.filtered_handler;

import std.algorithm;
import std.array;

import handy_httpd.components.handler;
import http_primitives;

/** 
 * An ordered, singly-linked list of filters to apply to a request context.
 */
class FilterChain {
    private HttpRequestFilter filter;
    private FilterChain next;

    /** 
     * Applies this chain link's filter to the request context.
     * Params:
     *   ctx = The request context.
     */
    void doFilter(ref HttpRequest request, ref HttpResponse response) {
        if (this.next !is null) {
            filter.apply(request, response, this.next);
        }
    }

    /** 
     * Appends the given filter chain to the end of this one.
     * Params:
     *   other = The other filter chain.
     * Returns: A reference to this filter chain.
     */
    FilterChain append(FilterChain other) {
        FilterChain link = this;
        while (link.next !is null) {
            link = link.next;
        }
        link.next = other;
        return this;
    }

    /** 
     * Builds a filter chain from the given list of filters.
     * Params:
     *   filters = The filters to construct the chain from.
     * Returns: The root filter chain element.
     */
    static FilterChain build(HttpRequestFilter[] filters) {
        if (filters.length < 1) return null;
        FilterChain[] links = filters.map!((f) {
            auto fc = new FilterChain();
            fc.filter = f;
            return fc;
        }).array;
        FilterChain root = links[0];
        FilterChain current = root;
        for (size_t i = 1; i < links.length; i++) {
            current.next = links[i];
            current = links[i];
        }
        current.next = new FilterChainEnd();
        return root;
    }

    unittest {
        import std.conv;

        assert(FilterChain.build([]) is null);

        class SimpleFilter : HttpRequestFilter {
            int id;
            this(int id) {
                this.id = id;
            }
            void apply(ref HttpRequest req, ref HttpResponse resp, FilterChain filterChain) {
                resp.headers.add("filter-" ~ id.to!string, id.to!string);
                filterChain.doFilter(req, resp);
            }
        }

        HttpRequestFilter f1 = new SimpleFilter(1);
        HttpRequestFilter f2 = new SimpleFilter(2);
        HttpRequestFilter f3 = new SimpleFilter(3);
        HttpRequestFilter[] filters = [f1, f2, f3];
        FilterChain fc = FilterChain.build(filters);

        assert(fc.filter == f1);
        assert(fc.next.filter == f2);
        assert(fc.next.next.filter == f3);
        assert(cast(FilterChainEnd) fc.next.next.next);
    }
}

private class FilterChainEnd : FilterChain {
    override void doFilter(ref HttpRequest request, ref HttpResponse response) {} // Don't do anything.
}

/** 
 * A filter that can be applied to a request context. If the filter determines
 * that it's okay to continue processing the request, it should call
 * `filterChain.doFilter(ctx);` to continue the chain. If the chain is not
 * continued, request processing ends at this filter, and the current response
 * is flushed to the client.
 */
interface HttpRequestFilter {
    void apply(ref HttpRequest request, ref HttpResponse response, FilterChain filterChain);
}

/** 
 * An alias for a function that can be used as a request filter.
 */
alias HttpRequestFilterFunction = void function (ref HttpRequest request, ref HttpResponse response, FilterChain);

/** 
 * Constructs a new request filter object from the given function.
 * Params:
 *   fn = The request filter function.
 * Returns: The request filter.
 */
HttpRequestFilter toFilter(HttpRequestFilterFunction fn) {
    return new class HttpRequestFilter {
        void apply(ref HttpRequest request, ref HttpResponse response, FilterChain filterChain) {
            fn(request, response, filterChain);
        }
    };
}

/** 
 * Simple implementation of a filter that just applies a request handler and
 * continues calling the filter chain.
 */
private class HandlerFilter : HttpRequestFilter {
    private HttpRequestHandler handler;

    this(HttpRequestHandler handler) {
        this.handler = handler;
    }

    void apply(ref HttpRequest request, ref HttpResponse response, FilterChain filterChain) {
        handler.handle(request, response);
        filterChain.doFilter(request, response);
    }
}

unittest {
    import http_primitives;
    import handy_httpd.components.builders;
    import slf4d;

    // Test that when applied, it calls the handler's handle() method, and then continues the filter chain.
    class TestingFilter : HttpRequestFilter {
        uint callCount;
        void apply(ref HttpRequest req, ref HttpResponse resp, FilterChain filterChain) {
            this.callCount++;
            filterChain.doFilter(req, resp);
        }
    }

    class TestingHandler : HttpRequestHandler {
        uint callCount;
        void handle(ref HttpRequest req, ref HttpResponse resp) {
            this.callCount++;
        }
    }


    auto testingHandler = new TestingHandler();
    auto testingFilter = new TestingFilter();
    auto handlerFilter = new HandlerFilter(testingHandler);
    HttpRequestFilter[] filters = cast(HttpRequestFilter[])[handlerFilter, testingFilter];
    auto filterChain = FilterChain.build(filters);
    HttpRequest req = buildRequest(Method.GET, "/test");
    HttpResponse resp = buildDiscardingResponse();
    filterChain.doFilter(req, resp);
    // Assert that both the handler filter, and the subsequent testing filter were called.
    assert(testingHandler.callCount == 1);
    assert(testingFilter.callCount == 1);
}

/** 
 * A request handler that can apply a series of filters before and after a
 * request is ultimately handled by a handler. The filtered request handler
 * prepares a filter chain that looks something like this:
 * ```
 * pre-request filters -> handler -> post-request filters
 * ```
 * 
 * When a request is handled by this handler, it will be passed on to the above
 * filter chain for processing. If the handler throws an exception, the filter
 * chain will be aborted, and the exception will be immediately handled by the
 * server's configured exception handler.
 */
class FilteredRequestHandler : HttpRequestHandler {
    private FilterChain filterChain;

    /**
     * Constructs a filtered request handler that simply applies a given filter
     * chain to any incoming requests.
     * Params:
     *   filterChain = The filter chain to apply to requests.
     */
    this(FilterChain filterChain) {
        this.filterChain = filterChain;
    }

    /**
     * Constructs a filtered request handler that applies pre-request filters,
     * then handles a request, and then post-request filters.
     * Params:
     *   handler = The handler for requests.
     *   preRequestFilters = Filters to run, in order, before the handler.
     *   postRequestFilters = Filters to run, in order, after the handler.
     */
    this(
        HttpRequestHandler handler,
        HttpRequestFilter[] preRequestFilters = [],
        HttpRequestFilter[] postRequestFilters = []
    ) {
        this(FilterChain.build(
            preRequestFilters ~ [cast(HttpRequestFilter) new HandlerFilter(handler)] ~ postRequestFilters
        ));
    }

    void handle(ref HttpRequest request, ref HttpResponse response) {
        filterChain.doFilter(request, response);
    }
}
