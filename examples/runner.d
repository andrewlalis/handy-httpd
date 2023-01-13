#!/usr/bin/env rdmd
import std.stdio;
import std.process;
import std.path;
import std.file;
import std.algorithm;
import std.typecons;
import std.array;
import core.thread;

int main(string[] args) {
    string[] exampleDirs = [];
    foreach (entry; dirEntries(".", SpanMode.shallow, false)) {
        if (entry.isDir) exampleDirs ~= entry.name;
    }

    Thread[] processThreads = [];
    foreach (dir; exampleDirs) {
        auto nullablePid = runExample(dir);
        if (!nullablePid.isNull) {
            Thread processThread = new Thread(() {
                Pid pid = nullablePid.get();
                int result = pid.wait();
                writefln!"Example %s exited with code %d."(dir, result);
            });
            processThread.start();
            processThreads ~= processThread;
        }
    }

    foreach (thread; processThreads) {
        thread.join();
    }
    return 0;
}

Nullable!Pid runExample(string dir) {
    writefln!"Running example: %s"(dir);
    // Prepare new standard streams for the example program.
    File newStdout = File(buildPath(dir, "stdout.log"), "w");
    File newStderr = File(buildPath(dir, "stderr.log"), "w");
    File newStdin = File.tmpfile();
    if (exists(buildPath(dir, "dub.json"))) {
        // Run normal dub project.
        Nullable!Pid result;
        result = spawnProcess(
            ["dub", "run"],
            newStdin,
            newStdout,
            newStderr,
            null,
            Config.none,
            dir
        );
        return result;
    } else {
        // Run single-file project.
        string executableFile = null;
        foreach (entry; dirEntries(dir, SpanMode.shallow, false)) {
            if (entry.name.endsWith(".d")) {
                executableFile = entry.name;
                break;
            }
        }
        if (executableFile !is null) {
            Nullable!Pid result;
            result = spawnProcess(
                ["dub", "run", "--single", baseName(executableFile)],
                newStdin,
                newStdout,
                newStderr,
                null,
                Config.none,
                dir
            );
            return result;
        } else {
            return Nullable!Pid.init;
        }
    }
}