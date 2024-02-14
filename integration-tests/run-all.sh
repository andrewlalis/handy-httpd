#!/usr/bin/env bash

cd file-test
java Tests.java
cd ..

cd multipart
dub run --single server.d
cd ..

cd speed-test
dub run
cd ..
