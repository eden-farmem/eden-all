#!/bin/bash

sudo apt-get install cmake libgflags-dev libsnappy-dev
sudo sysctl -w vm.unprivileged_userfaultfd=1

VERSION=6.15.2
wget https://github.com/facebook/rocksdb/archive/v${VERSION}.tar.gz -O rocksdb.tar.gz
tar -zxvf rocksdb.tar.gz
rm rocksdb.tar.gz
mv rocksdb-${VERSION} rocksdb
cd rocksdb
mkdir -p build && cd build
cmake -DCMAKE_BUILD_TYPE=Release -DWITH_SNAPPY=bundled .. && cmake --build . -j8