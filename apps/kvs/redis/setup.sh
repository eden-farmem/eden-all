#!/bin/bash
sudo apt-get install -y redis # for redis-benchmark
sudo systemctl disable redis-server.service
sudo sysctl vm.overcommit_memory=1
git clone https://github.com/redis/redis
cd redis
git checkout 6.0.16
make MALLOC=libc
