#!/bin/bash
sudo systemctl disable memcached.service
sudo apt-get install libevent-dev
sudo sysctl vm.overcommit_memory=1

# get server
git clone https://github.com/memcached/memcached
pushd memcached
git checkout 1.6.14
./autogen.sh
./configure
make
popd


# get client
https://github.com/idning/mc-benchmark
pushd mc-benchmark
make
popd