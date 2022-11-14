/**
 * Simple logging module which considers a server's settings to determine how
 * verbose to be.
 */
module handy_httpd.logger;

import std.stdio;
import std.traits;
import std.string;
import handy_httpd.server_config;

/** 
 * A logger that exposes some simple functions for plain and formatted log
 * messages, using a bound server configuration.
 */
struct ServerLogger {
    private ServerConfig* config;

    void info(T...)(T args) {
        writeln(args);
    }

    void infoV(T...)(T args) {
        if (config.verbose) info(args);
    }

    void infoF(alias fmt, A...)(A args) if (isSomeString!(typeof(fmt))) {
        info(format!(fmt)(args));
    }

    void infoFV(alias fmt, A...)(A args) if (isSomeString!(typeof(fmt))) {
        if (config.verbose) infoF!(fmt)(args);
    }
}
