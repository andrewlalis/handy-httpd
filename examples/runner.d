#!/usr/bin/env rdmd
module examples.runner;

import std.stdio;
import std.process;
import std.conv;
import std.path;
import std.file;
import std.string;
import std.algorithm;
import std.typecons;
import std.array;
import core.thread;

interface Example {
    string name() const;
    Pid run(string[] args) const;
    Pid test() const;
    string[] requiredFiles() const;
}

class DubSingleFileExample : Example {
    private string workingDir;
    private string filename;

    this(string workingDir, string filename) {
        this.workingDir = workingDir;
        this.filename = filename;
    }

    this(string filename) {
        this(".", filename);
    }

    string name() const {
        if (workingDir != ".") return workingDir;
        return filename[0..$-2];
    }

    Pid run(string[] args) const {
        string[] cmd = ["dub", "run", "--single", filename];
        if (args.length > 0) {
            cmd ~= "--";
            cmd ~= args;
        }
        return spawnProcess(
            cmd,
            std.stdio.stdin,
            std.stdio.stdout,
            std.stdio.stderr,
            null,
            Config.none,
            workingDir
        );
    }

    Pid test() const {
        return spawnProcess(
            ["dub", "build", "--single", filename],
            std.stdio.stdin,
            std.stdio.stdout,
            std.stdio.stderr,
            null,
            Config.none,
            workingDir
        );
    }

    string[] requiredFiles() const {
        if (workingDir == ".") {
            return [filename];
        } else {
            return [workingDir];
        }
    }
}

class DubSingleFileUnitTestExample : Example {
    private string filename;

    this(string filename) {
        this.filename = filename;
    }

    string name() const {
        return filename[0..$-2];
    }

    Pid run(string[] args) const {
        return spawnProcess(
            ["dub", "test", "--single", filename] ~ args
        );
    }

    Pid test() const {
        return run([]);
    }

    string[] requiredFiles() const {
        return [filename];
    }
}

const Example[] EXAMPLES = [
    new DubSingleFileExample("hello-world.d"),
    new DubSingleFileExample("file-upload.d"),
    new DubSingleFileExample("using-headers.d"),
    new DubSingleFileExample("path-handler.d"),
    new DubSingleFileExample("static-content-server", "content_server.d"),
    new DubSingleFileExample("websocket", "server.d"),
    new DubSingleFileUnitTestExample("handler-testing.d")
];

int main(string[] args) {
    if (args.length > 1 && toLower(args[1]) == "clean") {
        return cleanExamples();
    } else if (args.length > 1 && toLower(args[1]) == "list") {
        writefln!"The following %d examples are available:"(EXAMPLES.length);
        foreach (example; EXAMPLES) {
            writefln!" - %s"(example.name);
        }
        return 0;
    } else if (args.length > 1 && toLower(args[1]) == "run") {
        return runExamples(args[2..$]);
    } else if (args.length > 1 && toLower(args[1]) == "test") {
        return testExamples();
    }
    writeln("Nothing to run.");
    return 0;
}

int cleanExamples() {
    string currentPath = getcwd();
    string currentDir = baseName(currentPath);
    if (currentDir != "examples") {
        stderr.writeln("Not in the examples directory.");
        return 1;
    }

    foreach (DirEntry entry; dirEntries(currentPath, SpanMode.shallow, false)) {
        string filename = baseName(entry.name);
        if (shouldRemove(filename)) {
            if (entry.isFile) {
                std.file.remove(entry.name);
            } else {
                std.file.rmdirRecurse(entry.name);
            }
        }
    }

    return 0;
}

bool shouldRemove(string filename) {
    bool required = false;
    foreach (example; EXAMPLES) {
        if (canFind(example.requiredFiles, filename)) {
            required = true;
            break;
        }
    }
    if (!required) {
        return filename != ".gitignore" &&
            filename != "runner" &&
            filename != "runner.exe" &&
            !endsWith(filename, ".d") &&
            !endsWith(filename, ".md");
    }
    return false;
}

int runExamples(string[] args) {
    if (args.length > 0) {
        string exampleName = strip(toLower(args[0]));
        if (exampleName == "all") {
            ushort port = 8080;
            Pid[] pids = [];
            foreach (example; EXAMPLES) {
                if (cast(DubSingleFileUnitTestExample) example) {
                    pids ~= example.run([]);
                } else {
                    pids ~= example.run([port.to!string]);
                    port++;
                }
            }
            foreach (pid; pids) {
                pid.wait();
            }
            return 0;
        }
        foreach (example; EXAMPLES) {
            if (example.name == exampleName) {
                writefln!"Running example: %s"(example.name);
                return example.run(args[1..$]).wait();
            }
        }
        stderr.writefln!
            "\"%s\" does not refer to any known example. Use the \"list\" command to see available examples."
            (exampleName);
        return 1;
    } else {
        writeln("Select one of the examples below to run:");
        foreach (i, example; EXAMPLES) {
            writefln!"[%d]\t%s"(i + 1, example.name);
        }
        string input = readln().strip();
        try {
            uint idx = input.to!uint;
            if (idx < 1 || idx > EXAMPLES.length) {
                stderr.writefln!"%d is an invalid example number."(idx);
                return 1;
            }
            writefln!"Running example: %s"(EXAMPLES[idx - 1].name);
            return EXAMPLES[idx - 1].run([]).wait();
        } catch (ConvException e) {
            stderr.writefln!"\"%s\" is not a number."(input);
            return 1;
        }
    }
}

int testExamples() {
    foreach (example; EXAMPLES) {
        int exitCode = example.test().wait();
        if (exitCode != 0) {
            writefln!"Example %s failed with exit code %d."(example.name, exitCode);
            return exitCode;
        }
    }
    return 0;
}
