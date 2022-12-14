/**
 * This module contains a handler that applies filters to a request context
 * before (or after) handing it off to the proper handler.
 */
module handy_httpd.handlers.filtered_handler;

import std.algorithm;
import std.array;

import handy_httpd.components.handler;

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
    void doFilter(ref HttpRequestContext ctx) {
        if (next !is null) filter.apply(ctx, next);
    }

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
        return root;
    }

    unittest {
        import std.conv;
        class SimpleFilter : HttpRequestFilter {
            int id;
            this(int id) {
                this.id = id;
            }
            void apply(ref HttpRequestContext ctx, FilterChain filterChain) {
                ctx.response.addHeader("filter-" ~ id.to!string, id.to!string);
                filterChain.doFilter(ctx);
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
        assert(fc.next.next.next is null);
    }
}

/** 
 * A filter that can be applied to a request context.
 */
interface HttpRequestFilter {
    void apply(ref HttpRequestContext ctx, FilterChain filterChain);
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

    void apply(ref HttpRequestContext ctx, FilterChain filterChain) {
        handler.handle(ctx);
        filterChain.doFilter(ctx);
    }
}

/** 
 * A request handler that can apply a series of filters before and after a
 * request is ultimately handled by a handler.
 */
class FilteredRequestHandler : HttpRequestHandler {
    private FilterChain filterChain;

    this(HttpRequestHandler handler, FilterChain preRequest, FilterChain postRequest) {
        this.filterChain = new FilterChain();
        filterChain.filter = new HandlerFilter(handler);
        filterChain.next = postRequest;
        if (preRequest !is null) {
            filterChain = preRequest.append(filterChain);
        }
    }

    this(HttpRequestHandler handler, HttpRequestFilter[] preRequestFilters = [], HttpRequestFilter[] postRequestFilters = []) {
        this(
            handler,
            FilterChain.build(preRequestFilters),
            FilterChain.build(postRequestFilters)
        );
    }

    void handle(ref HttpRequestContext ctx) {
        filterChain.doFilter(ctx);
    }
}
