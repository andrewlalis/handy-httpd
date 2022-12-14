/**
 * Simple logging module which considers a server's settings to determine how
 * verbose to be.
 */
module handy_httpd.components.logger;

import std.stdio;
import std.traits;
import std.string;

import handy_httpd.components.config;

/** 
 * A logger that exposes some simple functions for plain and formatted log
 * messages, using a bound server configuration.
 */
struct ServerLogger {
    private ServerConfig* config;

    /** 
     * Writes an info log to stdout.
     * Params:
     *   args = The arguments to write.
     */
    void info(T...)(T args) {
        writeln(args);
    }

    /** 
     * Writes a log to stdout, if the server is configured for verbose output.
     * Params:
     *   args = The arguments to write.
     */
    void infoV(T...)(T args) {
        if (config.verbose) info(args);
    }

    /** 
     * Writes a formatted string to stdout.
     * Params:
     *   args = The arguments to the format string.
     */
    void infoF(alias fmt, A...)(A args) if (isSomeString!(typeof(fmt))) {
        info(format!(fmt)(args));
    }

    /** 
     * Writes a formatted string to stdout, if the server is configured for
     * verbose output.
     * Params:
     *   args = The arguments to the format string.
     */
    void infoFV(alias fmt, A...)(A args) if (isSomeString!(typeof(fmt))) {
        if (config.verbose) infoF!(fmt)(args);
    }
}
