#!/usr/bin/env rdmd
module build_ddoc;

import std.stdio;
import std.process;
import std.file;

const DOC_GEN_SRC = "ddoc-gen-src";
const DOC_OUT = "./src/.vuepress/public/ddoc";

int main() {
    if (exists(DOC_GEN_SRC)) {
        rmdirRecurse(DOC_GEN_SRC);
    }

    if (exists(DOC_OUT)) {
        rmdirRecurse(DOC_OUT);
    }

    Pid pid;
    int result;

    pid = spawnProcess(["git", "clone", "git@github.com:adamdruppe/adrdox.git", "--branch", "master", "--single-branch", DOC_GEN_SRC]);
    result = wait(pid);
    if (result != 0) {
        writefln!"git clone failed with exit code %d"(result);
        return 1;
    }

    string docsDir = getcwd();
    chdir(DOC_GEN_SRC);
    pid = spawnProcess("make");
    result = wait(pid);
    if (result != 0) {
        writefln!"make failed with exit code %d"(result);
        return 1;
    }
    
    chdir(docsDir);
    pid = spawnProcess([DOC_GEN_SRC ~ "/doc2", "-i", "-o", DOC_OUT, "../source"]);
    result = wait(pid);
    if (result != 0) {
        writefln!"ddoc generation failed with exit code %d"(result);
        return 1;
    }
    return 0;
}
