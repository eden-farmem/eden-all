#!/bin/bash
set -e

#
# Generate fault code locations
#

SCRIPT_PATH=`realpath $0`
SCRIPT_DIR=`dirname ${SCRIPT_PATH}`
DATADIR="${SCRIPT_DIR}/data"
ROOT_DIR="${SCRIPT_DIR}/../../"
ROOT_SCRIPTS_DIR="${ROOT_DIR}/scripts/"
TOOL_DIR="${ROOT_DIR}/fault-analysis/"
TMP_FILE_PFX="tmp_rocksdb_analysis_"

source ${ROOT_SCRIPTS_DIR}/utils.sh

# Experiments
pattern="01-18"; desc="trace"

# Get runs
runinfo=${TMP_FILE_PFX}runs
bash show.sh ${pattern} -d=${desc} -of=${runinfo}
cat ${runinfo}

app=rocksdb
for cutoff in 100 95; do
    result=results_rocksdb_${cutoff}.csv
    # if [ -f ${result} ]; then
    #     continue
    # fi

    # collect data
    echo "name,percent,loc,floc,local,app,lmemp" > $result
    for exp in $(csv_column "$runinfo" "Exp"); do
        echo $exp
        expdir=${DATADIR}/$exp
        localmem=$(cat $expdir/settings | grep "localmem:" | awk -F: '{ printf $2/1000000 }')
        localmemp=$(cat $expdir/settings | grep "localmempercent:" | awk -F: '{ printf $2 }')

        bash ${TOOL_DIR}/analysis/clean_trace.sh ${expdir}/traces/000_000.txt
        output=$(python3 ${TOOL_DIR}/analysis/trace_codebase.py -d ${DATADIR}/${exp}/traces/ -r -n ${app}_${cutoff} -c ${cutoff})
        echo "${output},${app},${localmemp}" >> $result
    done
done

# cleanup
rm -f ${TMP_FILE_PFX}*
