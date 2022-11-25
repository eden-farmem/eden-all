#!/bin/bash

#
# Collect OS virtual memory stats
#

APPNAME=$1  
while true
do
    cat /proc/vmstat   \
        | awk '{ printf "%s:%s,", $1, $2 } END { printf "\n" }' \
        | ts %s, 
    sleep 1
done