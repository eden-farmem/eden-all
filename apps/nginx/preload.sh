#!/bin/bash

while getopts t: flag
do
    case "${flag}" in
        t) time_exp=${OPTARG};;
    esac
done

sudo killall nginx
sleep 1
version="5.11"
#lib="/root/fault-analysis/tool/${version}/fltrace-debug.so"
lib="/root/fault-analysis/tool/${version}/fltrace.so"
# run tool
echo 0 | sudo tee /proc/sys/kernel/randomize_va_space #no ASLR
sudo sysctl -w vm.unprivileged_userfaultfd=1    # to run without sudo
# env="$env LD_PRELOAD=$lib"
# env="$env FLTRACE_LOCAL_MEMORY_MB=1"
# env="$env FLTRACE_MAX_MEMORY_MB=10000"
# env="$env FLTRACE_NHANDLERS=1"


mkdir -p logs
pushd logs
rm -r *

export LD_PRELOAD="$lib"
export FLTRACE_LOCAL_MEMORY_MB=1
export FLTRACE_MAX_MEMORY_MB=10000
export FLTRACE_NHANDLERS=1
nginx &
export -n LD_PRELOAD

nginx_pid=$!
echo "nginx_pid $nginx_pid"
strings /proc/$nginx_pid/environ
sleep $time_exp

# ps -e | grep nginx
# sleep 5
# ps -e | grep nginx