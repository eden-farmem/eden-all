#!/bin/bash -e

# function nginx () {
#     app_name=${FUNCNAME[0]}
#     pushd /root/eden-all/apps/nginx
#     if [ ! -d nginx ]; then
#         echo "${app_name} is not installed"
#         echo "Setting up ${app_name}"
#         ./setup.sh
#     fi
#     echo "Tracing ${app_name}"
#     ./trace.sh
#     echo "Analysing"
#     ./analyze.sh
#     popd
# }

# nginx
pushd () {
    command pushd "$@" > /dev/null
}

popd () {
    command popd "$@" > /dev/null
}

# percentage=("95" "90" "85" "80" "75" "70" "65" "60" "55" "50" "45" "40" "35" "30" "25" "20" "15" "10")
# percentage=("90" "80" "70" "60" "50" "40" "30" "20" "10")
percentage=("90")

function get_percentage_array() {

    one_hundred=$1
    #name a local variable derrived percentage that we passed in
    local -n derrived_percentages=$2
    derrived_percentages=()
    for p in ${percentage[@]}; do
        v=$(( $one_hundred*$p/100 ))
        v2=$(( $v/1000000 ))
        derrived_percentages+=(${v2})
    done
}

function most_recent_data_dir() {
    data_directory=$1

    latest_data_dir=`ls -tcl $data_directory | cut -d " " -f 9 | head -2 | tail -1`
    if [ ! -d "${data_directory}/$latest_data_dir" ]; then
        echo "$latest_data_dir is not a directory"
        exit
    fi

    echo ${data_directory}/${latest_data_dir}
}

function hundred_mem() {
    latest_data_dir=$1
    pushd $latest_data_dir
    line=`cat fault-stats.out | tail -1`
    dict=`echo $line | awk '{split($0,b,","); for (key in b) { print b[key]}}' | grep "memory_allocd" `
    hundred=`echo $dict | cut -d ":" -f 2`

    if [ $hundred == "" ]; then
        echo "one hundred percent of memory not calculated correctly"
        exit 1
    fi
    echo $hundred
    popd
}

#this returns the trace directory
function run_trace_merge_tool() {

    merge_script="/root/eden-all/scripts/parse_fltrace_samples.py"
    if [ ! -f $merge_script ]; then
        echo "Merge script not found [${merge_script}] unable to process raw trace. Perahps the path is wrong?"
    fi

    latest_data_dir=`ls -tcl data | cut -d " " -f 9 | head -2 | tail -1`
    if [ ! -d "data/$latest_data_dir" ]; then
        echo "$latest_data_dir is not a directory"
        exit 1
    fi

    trace=`ls --format=single-column "data/$latest_data_dir" | grep fault-samples`
    trace_location="data/${latest_data_dir}/${trace}"
    if [ ! -f $trace_location ]; then
        echo " ${trace_location} is not a file"
        exit 1
    fi

    # echo $trace_location
    trace_dir="data/${latest_data_dir}/trace"
    mkdir -p ${trace_dir}
    processed_trace="${trace_dir}/000_000.txt"

    python $merge_script -i $trace_location -o $processed_trace

    echo ${trace_dir}

}

function run_fault_tool() {
    fault_analysis_tool="../fault-analysis/analysis/trace_codebase.py"
    results="data/results.txt"
    python ${fault_analysis_tool} -d $trace_dir -n "nginx_100" -c 100 -R > $results
    python ${fault_analysis_tool} -d $trace_dir -n "nginx_95" -c 95 -r >> $results
    cat $results

}



function run_sweep() {
    app=$1
    echo "Running Sweep on app: $app"
    
    app_dir="../apps/$app"
    if [ ! -d $app_dir ]; then
        echo "${app_dir} does not exit. This test is going to fail"
        exit 1
    fi

    pushd $app_dir
    if [ ! -f "trace.sh" ]; then
        echo "$app does not seem to have a trace.sh. This test requires that trace.sh exists and take a local memory argument"
        exit 1
    fi


    result_dirs=()
    #collect the 100% memory benchmark
    #by default the program runs with 100% local memory

    ./trace.sh --lmemp=100
    result_dirs+=(`run_trace_merge_tool`)

    for d in ${result_dirs[@]}; do
        echo "printing dirs after 100% run"
        echo $d
    done

    latest=`most_recent_data_dir data`
    #for this first experiment collect all other values based on 100% memory
    one_hundred_percent_memory=`hundred_mem $latest`
    echo $one_hundred_percent_memory

    local memory_percent_array
    get_percentage_array $one_hundred_percent_memory memory_percent_array

    declare -a memory_percent_array

    #now we have all values for lower memory percentages

    for i in ${!memory_percent_array[@]}; do
        echo "running $app with memory percent ${memory_percent_array[i]}"
        ./trace.sh --localmem="${memory_percent_array[i]}" --lmemp="${percentage[i]}"
        result_dirs+=(`run_trace_merge_tool`)
    done

    # declare -p percent_array
    mkdir -p current_run
    for i in ${!result_dirs[@]}; do
        echo "${result_dirs[i]}"
        cp data/${result_dirs[i]} current_run/${percentage[i]}
    done

}

function run_merge_tool() {
    echo "running merge tool"
    directory=$1
    merge_script="/root/eden-all/scripts/parse_fltrace_samples.py"
    clean_script="/root/eden-all/fault-analysis/analysis/clean_trace.sh"
    pushd $directory

    mkdir -p traces
    processed_trace="traces/000_000.txt"

    trace=`ls --format=single-column  | grep fault-samples`
    trace_location="./${trace}"
    if [ ! -f $trace_location ]; then
        echo " ${trace_location} is not a file"
        exit
    fi

    python $merge_script -i $trace_location -o $processed_trace
    ${clean_script} $processed_trace

    popd

}

function run_analysis() {
    app=$1
    if [ ! -d "data/$app" ]; then
        echo "we need to have a data directory for $app at data/$app to run this analysis"
    fi

    dirs=`ls --format=single-column  data/$app`

    fault_analysis_tool="/root/eden-all/fault-analysis/analysis/trace_codebase.py"
    if [ -f results ]; then
        rm results
    fi

    for d in ${dirs[@]}; do
        pushd "data/${app}/${d}"
        memory=`cat settings | grep localmempercent | cut -d ":" -f 2`
        # if [ ! -d traces ] || [ ! -f traces/000_000.txt ]; then
            run_merge_tool "./" 

        # fi
        python ${fault_analysis_tool} -d "./" -n "${app}_$memory" -c 100 -r -z >> results
        python ${fault_analysis_tool} -d "./" -n "${app}_$memory" -c 95 -r -z >> results
        popd

    done

}

run_sweep "apache"

# run_analysis "apache"