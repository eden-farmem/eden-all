#!/bin/bash
sudo apt-get install -y redis
sudo systemctl disable redis-server.service
sudo sysctl vm.overcommit_memory=1