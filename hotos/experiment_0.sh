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

EDEN_ROOT=`realpath ../`
NFS_DATA_DIR='/home/ssgrant/eden-data/'
mkdir -p $NFS_DATA_DIR
EXP_NAME=experiment_001-$(date '+%m-%d-%H-%M-%S')
EXP_DATA_DIR=${NFS_DATA_DIR}/${EXP_NAME}

# nginx
pushd () {
    command pushd "$@" > /dev/null
}

popd () {
    command popd "$@" > /dev/null
}

# percentage=("95" "90" "85" "80" "75" "70" "65" "60" "55" "50" "45" "40" "35" "30" "25" "20" "15" "10" "5")
# percentage=("90" "80" "70" "60" "50" "40" "30" "20" "10")
percentage=("10")
# percentage=("90")

function get_percentage_array() {

    one_hundred=$1
    #name a local variable derrived percentage that we passed in
    local -n derrived_percentages=$2
    derrived_percentages=()
    for p in ${percentage[@]}; do
        v=$(( $one_hundred*$p/100 ))
        derrived_percentages+=(${v})
    done
}

function most_recent_data_dir() {
    data_directory=$1

    # ls ${data_directory}
    if [ ! -d ${data_directory} ]; then
        echo "${data_directory} root data directory ${data_directory} does not exist, exiting hard!"
        exit 1
    fi

    latest_data_dir=`ls -tcl ${data_directory} | awk '{ print $9 }' | head -2 | tail -1`
    # latest_data_dir=`ls -tcl ${data_directory} | awk '{ print $9 }'

    if [ ! -d "${data_directory}/${latest_data_dir}" ]; then
        echo "${latest_data_dir}_does_not_seem_to_be_a_directory..."
        echo "${data_directory} something funning is happening"
        exit
    fi

    echo "`realpath ${data_directory}/${latest_data_dir}`"
}

function hundred_mem() {
    latest_data_dir=$1
    pushd $latest_data_dir
    fault_mem_script=${EDEN_ROOT}/scripts/parse_fltrace_stat.py
    stats=`ls fault-stats-*`
    hundred=`python ${fault_mem_script} --maxrss -i $stats`
    # dict=`echo $line | awk '{split($0,b,","); for (key in b) { print b[key]}}' | grep "memory_allocd" `
    # hundred=`echo $dict | cut -d ":" -f 2`
    if [ $hundred == "" ]; then
        echo "one hundred percent of memory not calculated correctly"
        exit 1
    fi
    echo $hundred
}

function run_merge_tool() {
    echo "running merge tool"
    directory=$1
    merge_script="${EDEN_ROOT}/scripts/parse_fltrace_samples.py"
    clean_script="${EDEN_ROOT}/fault-analysis/analysis/clean_trace.sh"
    pushd $directory

    mkdir -p trace
    processed_trace="trace/000_000.txt"

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

#this returns the trace directory
function run_trace_merge_tool() {

    app=$1

    merge_script="${EDEN_ROOT}/scripts/parse_fltrace_samples.py"
    clean_script="${EDEN_ROOT}/fault-analysis/analysis/clean_trace.sh"
    if [ ! -f $merge_script ]; then
        echo "Merge script not found [${merge_script}] unable to process raw trace. Perahps the path is wrong?"
    fi

    latest_data_dir=`ls -tcl data | awk '{ print $9 }' | head -2 | tail -1`
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

    if [ ! -f "trace.sh" ]; then
        echo "trace.sh not found for app ${app} running ls"
        ls
        exit 1
    fi
    binary_location=`./trace.sh -b`
    python $merge_script -i $trace_location -o $processed_trace -b ${binary_location}
    $clean_script $processed_trace

    app_data_dir=${EXP_DATA_DIR}/${app}
    mkdir -p ${app_data_dir}
    mv data/${latest_data_dir} ${app_data_dir}/${latest_data_dir}
    echo "${app_data_dir}/${latest_data_dir}"

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
    app_dir=$2
    echo "Running Sweep on app: $app"

    if [ ! -d ${EXP_DATA_DIR} ]; then
        mkdir -p ${EXP_DATA_DIR}
    fi
    
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


    result_dirs+=(`run_trace_merge_tool $app`)

    for d in ${result_dirs[@]}; do
        echo "printing dirs after 100% run $d"
    done

    app_data_dir=${EXP_DATA_DIR}/${app}
    latest=`most_recent_data_dir ${app_data_dir}`
    #for this first experiment collect all other values based on 100% memory
    echo "collected the latest data directory $latest"

    one_hundred_percent_memory=`hundred_mem $latest`
    echo "One hundered percent memory: $one_hundred_percent_memory for $app"

    local memory_percent_array
    get_percentage_array $one_hundred_percent_memory memory_percent_array

    declare -a memory_percent_array

    #now we have all values for lower memory percentages

    for i in ${!memory_percent_array[@]}; do
        echo "running $app at ${percentage[i]}% local memory ${memory_percent_array[i]} ${one_hundred_percent_memory}"
        ./trace.sh --localmem="${memory_percent_array[i]}" --lmemp="${percentage[i]}"
        result_dirs+=(`run_trace_merge_tool $app`)
    done

    popd

}


function run_analysis() {
    app=$1
    app_dir=$2


    # latest="`most_recent_data_dir ${NSF_DATA_DIR}`"
    latest=`most_recent_data_dir ${NFS_DATA_DIR}`
    echo "Latest Results Directory: $latest"

    if [ ! -d "${latest}/${app}" ]; then
        echo "we need to have a data directory for $app at ${latest}/$app to run this analysis"
    fi

    dirs=`ls --format=single-column  ${latest}/$app`

    fault_analysis_tool="${EDEN_ROOT}/fault-analysis/analysis/trace_codebase.py"

    result_100_name="results_${app}_100.csv"
    result_95_name="results_${app}_95.csv"
    result_files=("$result_100_name" "$result_95_name")
    percent=("100" "95")

    for file in ${result_files[@]}; do
        if [ -f data/${file} ]; then
            rm data/${file}
        fi
    done

    for d in ${dirs[@]}; do
        pushd "${latest}/${app}/${d}"
        memory=`cat settings | grep localmempercent | cut -d ":" -f 2`
        if [ ! -d trace ] || [ ! -f trace/000_000.txt ]; then
            run_merge_tool "./" 
        fi

        #check if the files exist, if they do not then inject the header, otherwise run as normal
        for i in ${!result_files[@]}; do
            file=${result_files[i]}
            p=${percent[i]}
            echo $file $p
            echo $file
            rel_file="../../${file}"
            if [ ! -f "$rel_file" ]; then
                echo "first line"
                header_arg="-R"
            else
                header_arg="-r"
            fi
            python ${fault_analysis_tool} -d "trace" -n "${app}_$memory" -c ${p} ${header_arg} -z --local >> $rel_file
            truncate -s-1 $rel_file
            echo "${app},${memory},native" >> $rel_file

            if [ $header_arg == "-R" ]; then
                echo "running sed"
                sed -i ' 1 s/.*/&,app,lmemp,input/' $rel_file
            fi

        done

        popd

    done

    # pushd data
    # mkdir -p latest_results
    # mv *.csv latest_results
    # popd


}

function run_delete() {
    app_dir=$1
    echo "Running Delete on app: $app_dir"
    
    if [ ! -d $app_dir ]; then
        echo "${app_dir} does not exit. This test is going to fail"
        return
    fi

    if [ ! -d ${app_dir}/data ]; then
        echo "${app_dir}/data does not exit. so we will not delete."
        return
    fi

    rm -r ${app_dir}/data
}

# run_sweep "apache" "../apps/apache"
# run_analysis "apache"

function run_func() {
    app_dir=$1
    name=`basename $app_dir`
    # run_delete $app_dir
    run_sweep $name $app_dir
    run_analysis $name $app_dir

}

function run_tests() {
    apps=(
        # "../apps/apache"
        # "../apps/nginx"
        "../apps/crono/crono/apps/apsp"
        "../apps/crono/crono/apps/bc"
        "../apps/crono/crono/apps/bfs"
        "../apps/crono/crono/apps/community"
        "../apps/crono/crono/apps/connected-components"
        "../apps/crono/crono/apps/dfs"
        "../apps/crono/crono/apps/pagerank"
        "../apps/crono/crono/apps/sssp"
        "../apps/crono/crono/apps/triangle-counting"
        "../apps/crono/crono/apps/tsp"
    )

    #itterate through the tests    
    for app_dir in ${apps[@]}; do
        run_func $app_dir &
    done
    wait



}

run_tests -d

# run_sweep "bfs" "../apps/crono/crono/apps/bfs"
# run_analysis "bfs"