#!/bin/bash

#
# Collect Frontswap stats
#

while true
do
    time=$(date +%s)
    line="$time"
    for f in `ls /sys/kernel/debug/frontswap`; do
        line="$line,$f:`cat /sys/kernel/debug/frontswap/$f`"
    done
    echo $line
    sleep 1
done