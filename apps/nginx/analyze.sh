#!/bin/bash

merge_script="../../scripts/parse_fltrace_samples.py"
latest_data_dir=`ls -tcl data | cut -d " " -f 9 | head -2 | tail -1`

if [ ! -d "data/$latest_data_dir" ]; then
    echo "$latest_data_dir is not a directory"
    exit
fi

trace=`ls --format=single-column "data/$latest_data_dir" | grep fault-samples`
trace_location="data/${latest_data_dir}/${trace}"
if [ ! -f $trace_location ]; then
    echo " ${trace_location} is not a file"
    exit
fi

trace_dir="data/${latest_data_dir}/trace"
mkdir -p ${trace_dir}
processed_trace="${trace_dir}/000_000.txt"

python $merge_script -i $trace_location -o $processed_trace
fault_analysis_tool="../../fault-analysis/analysis/trace_codebase.py"

results="data/${latest_data_dir}/results.txt"
python ${fault_analysis_tool} -d $trace_dir -n "nginx_100" -c 100 -R > $results
python ${fault_analysis_tool} -d $trace_dir -n "nginx_95" -c 95 -r >> $results

cat $results

