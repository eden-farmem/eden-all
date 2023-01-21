#!/bin/bash
# set -e
#
# Generate fault code locations
#

SCRIPT_PATH=`realpath $0`
SCRIPT_DIR=`dirname ${SCRIPT_PATH}`
DATADIR="${SCRIPT_DIR}/data"
FAULT_DIR="${SCRIPT_DIR}/faults"
ROOT_DIR="${SCRIPT_DIR}/../../"
ROOT_SCRIPTS_DIR="${ROOT_DIR}/scripts/"
TRASH="${DATADIR}/trash"
TMP_FILE_PFX="tmp_rocksdb_faults_"

source ${ROOT_SCRIPTS_DIR}/utils.sh 
mkdir -p ${FAULT_DIR}

# Data
pattern="01-18";desc="trace";

runinfo=${TMP_FILE_PFX}runs
bash show.sh ${pattern} -d=${desc} -of=${runinfo}
# cat ${runinfo}

for expname in $(csv_column "$runinfo" "Exp"); do
    expdir=${DATADIR}/$expname
    localmem=$(cat $expdir/settings | grep "localmem:" | awk -F: '{ printf $2/1000000 }')
    localmemp=$(cat $expdir/settings | grep "localmempercent:" | awk -F: '{ printf $2 }')

    # find corresponding binary
    binfile=${SCRIPT_DIR}/rocksdb/build/db_bench 

    # locate fault samples
    faultsin=$(ls ${expdir}/fault-samples-*.out | head -1)
    if [ ! -f ${faultsin} ]; then 
        echo "no fault-samples-*.out found for ${app} at ${expdir}"
        exit 1
    fi

    mkdir -p ${expdir}/traces
    if [ -f ${expdir}/traces/000_000.txt ]; then
        echo "traces already exist for ${app} at ${expdir}"
        continue
    fi

    allfaultsin=$(ls ${expdir}/fault-samples-*.out)
    python3 ${ROOT_SCRIPTS_DIR}/parse_fltrace_samples.py -i ${allfaultsin}    \
        -b ${binfile} > ${expdir}/traces/000_000.txt
done

# cleanup
rm -f ${TMP_FILE_PFX}*