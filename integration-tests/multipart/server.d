#!/usr/bin/env dub
/+ dub.sdl:
    dependency "handy-httpd" path="../../"
    dependency "requests" version="~>2.1.3"
+/
module multipart_integration_test;

import handy_httpd;
import slf4d;
import slf4d.default_provider;
import requests;

import std.stdio;
import std.json;
import std.path;
import std.file;
import std.string;
import std.digest : toHexString;
import std.digest.md : md5Of;
import core.thread;

void main() {
    auto provider = new shared DefaultProvider(true, Levels.DEBUG);
    configureLoggingProvider(provider);

    HttpServer server = getServer();
    Thread serverThread = new Thread(&server.start);
    serverThread.start();
    while (!server.isReady()) {
        info("Waiting for server to come online.");
        Thread.sleep(msecs(10));
    }
    info("Server is online. Starting tests.");

    // A first test for general acceptance of form data.
    MultipartForm form;
    form.add(formData("name", "any name"));
    form.add(formData(
        "file",
        File("sample-file-1.txt", "rb"),
        ["filename": "sample-file-1.txt", "Content-Type": "text/plain"]
    ));
    form.add(formData(
        "file2",
        File("sample-file-2.nbt", "rb"),
        ["filename": "sample-file-2.nbt", "Content-Type": "application/octet-stream"]
    ));
    Buffer!ubyte responseContent = postContent("http://localhost:8080", form);
    JSONValue responseJson = parseJSON(responseContent.toString());
    assert(responseJson.type() == JSONType.ARRAY);
    assert(responseJson.array.length == 3);
    char[32] hash;

    assert(responseJson.array[0].object["name"] == JSONValue("name"));
    assert(responseJson.array[0].object["size"] == JSONValue(8));
    hash = toHexString(md5Of("any name"));
    assert(responseJson.array[0].object["md5Hash"] == JSONValue(hash.idup));

    assert(responseJson.array[1].object["name"] == JSONValue("file"));
    assert(responseJson.array[1].object["size"] == JSONValue(getSize("sample-file-1.txt")));
    hash = toHexString(md5Of(std.file.read("sample-file-1.txt")));
    assert(responseJson.array[1].object["md5Hash"] == JSONValue(hash.idup));
    
    assert(responseJson.array[2].object["name"] == JSONValue("file2"));
    assert(responseJson.array[2].object["size"] == JSONValue(getSize("sample-file-2.nbt")));
    hash = toHexString(md5Of(std.file.read("sample-file-2.nbt")));
    assert(responseJson.array[2].object["md5Hash"] == JSONValue(hash.idup));

    // A second test to make sure we can handle larger files.
    MultipartForm form2;
    form2.add(formData(
        "file",
        File("sample-file-3-lg.nbt", "rb"),
        ["filename": "sample-file-3-lg.nbt", "Content-Type": "application/octet-stream"]
    ));
    Buffer!ubyte responseContent2 = postContent("http://localhost:8080", form2);
    JSONValue responseJson2 = parseJSON(responseContent2.toString());
    assert(responseJson2.array.length == 1);
    JSONValue obj = responseJson2.array[0];
    assert(obj.object["name"] == JSONValue("file"));
    assert(obj.object["size"] == JSONValue(getSize("sample-file-3-lg.nbt")));
    hash = toHexString(md5Of(std.file.read("sample-file-3-lg.nbt")));
    assert(obj.object["md5Hash"] == JSONValue(hash.idup));

    server.stop();
    serverThread.join();
}

HttpServer getServer() {
    ServerConfig config = ServerConfig.defaultValues();
    config.workerPoolSize = 3;
    config.port = 8080;
    return new HttpServer((ref HttpRequestContext ctx) {
        MultipartFormData data = ctx.request.readBodyAsMultipartFormData();
        JSONValue result = JSONValue(string[].init);
        foreach (MultipartElement element; data.elements) {
            JSONValue elementJson = JSONValue(string[string].init);
            elementJson.object["name"] = JSONValue(element.name);
            elementJson.object["size"] = JSONValue(element.content.length);
            char[32] hash = toHexString(md5Of(element.content));
            elementJson.object["md5Hash"] = JSONValue(hash.idup);
            result.array ~= elementJson;
        }
        ctx.response.writeBodyString(result.toJSON(), "application/json");
    }, config);
}
