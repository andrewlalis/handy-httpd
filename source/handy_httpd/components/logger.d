/**
 * Simple logging module which considers a server's settings to determine how
 * verbose to be.
 */
module handy_httpd.components.logger;

/** 
 * The various levels of logging that are available.
 */
enum LogLevel {
    DEBUG     = 10,
    INFO      = 20,
    WARNING   = 30,
    ERROR     = 40
}

private string getLogLevelName(LogLevel level) {
    if (level <= LogLevel.DEBUG) return "DEBUG";
    if (level <= LogLevel.INFO) return "INFO";
    if (level <= LogLevel.WARNING) return "WARNING";
    return "ERROR";
}

/** 
 * A logger that is a bit smarter than standard IO, and is able to output
 * formatted messages to stdout and stderr, and consider the request context
 * from which it was created.
 */
struct ContextLogger {
    import handy_httpd.components.worker;
    import std.traits;
    import std.string;
    import std.stdio;
    import std.datetime;

    /** 
     * The name of this logger, which will appear in log messages.
     */
    private string name = "Logger";

    /** 
     * The log level that this logger will use. Only logs of a severity equal
     * to or greater than this level will be shown.
     */
    private LogLevel level = LogLevel.DEBUG;

    /** 
     * Initializes a logger for a server's worker thread, taking configuration
     * properties from the worker's server.
     * Params:
     *   worker = The worker to initialize from.
     * Returns: A context logger.
     */
    public static ContextLogger forWorkerThread(ServerWorkerThread worker) {
        return ContextLogger(
            worker.name,
            worker.getServer().config.defaultHandlerLogLevel
        );
    }

    /** 
     * Initializes a logger using the same level as the given logger, and the
     * given name.
     * Params:
     *   other = The other logger.
     *   name = The name of this logger.
     * Returns: A context logger.
     */
    public static ContextLogger from(ContextLogger other, string name) {
        return ContextLogger(
            name,
            other.level
        );
    }

    /** 
     * Logs a message.
     * Params:
     *   level = The log level to use.
     *   args = The arguments to log.
     */
    public void log(T...)(LogLevel level, T args) const {
        if (level < this.level) return;

        File outputStream = stdout;
        if (level >= LogLevel.WARNING) {
            outputStream = stderr;
        }

        SysTime now = Clock.currTime();
        string logPrefix = format!"[%s %s] %s: "(
            this.name,
            getLogLevelName(level),
            now.toISOExtString(0)
        );
        outputStream.writeln(logPrefix, args);
    }

    public void logF(alias fmt, T...)(LogLevel level, T args) const if (isSomeString!(typeof(fmt))) {
        this.log(level, format!(fmt)(args));
    }

    public void debug_(T...)(T args) const {
        this.log!T(LogLevel.DEBUG, args);
    }

    public void debugF(alias fmt, T...)(T args) const if (isSomeString!(typeof(fmt))) {
        this.logF!(fmt, T)(LogLevel.DEBUG, args);
    }

    public void info(T...)(T args) const {
        this.log!T(LogLevel.INFO, args);
    }

    public void infoF(alias fmt, T...)(T args) const if (isSomeString!(typeof(fmt))) {
        this.logF!(fmt, T)(LogLevel.INFO, args);
    }

    public void warn(T...)(T args) const {
        this.log!T(LogLevel.WARNING, args);
    }

    public void warnF(alias fmt, T...)(T args) const if (isSomeString!(typeof(fmt))) {
        this.logF!(fmt, T)(LogLevel.WARNING, args);
    }

    public void error(T...)(T args) const {
        this.log!T(LogLevel.ERROR, args);
    }

    public void errorF(alias fmt, T...)(T args) const if (isSomeString!(typeof(fmt))) {
        this.logF!(fmt, T)(LogLevel.ERROR, args);
    }
}

unittest {
    auto logger = ContextLogger("Test:ContextLogger", LogLevel.DEBUG);

    // Ensure that all the various functions work at runtime.
    logger.log(LogLevel.DEBUG, "log DEBUG test");
    logger.logF!"logF DEBUG test: %d %s"(LogLevel.DEBUG, 123, "Hello World!");

    const string s = "Hello world!";
    logger.debug_("debug_ test");
    logger.debugF!"debugF test %d %s"(123, s);

    logger.info("info test");
    logger.infoF!"infoF test %d"(123);
    
    logger.warn("warn test");
    logger.warnF!"warnF test %d"(123);

    logger.error("error test");
    logger.errorF!"errorF test %d"(123);
}
