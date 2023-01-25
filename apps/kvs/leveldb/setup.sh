#!/bin/bash

sudo apt-get install cmake libgflags-dev libsnappy-dev
sudo sysctl -w vm.unprivileged_userfaultfd=1

wget https://github.com/google/leveldb/archive/1.22.tar.gz -O leveldb.tar.gz
tar -zxvf leveldb.tar.gz
rm leveldb.tar.gz
mv leveldb-1.22 leveldb
cd leveldb
mkdir -p build && cd build
cmake -DCMAKE_BUILD_TYPE=Release .. && cmake --build .