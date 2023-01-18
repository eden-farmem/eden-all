#!/bin/bash

function run_apps () {
    for app in apps; do
        cd app
        for i in local_mem; do
            ./run.sh
            fault_analysis -d apps/$app/traces
            get_usage.sh >> results.txt
        done
    .
}