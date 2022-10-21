#
# Output fault locations
#

SCRIPT_PATH=`realpath $0`
SCRIPT_DIR=`dirname ${SCRIPT_PATH}`
DATADIR="${SCRIPT_DIR}/data"
FAULT_DIR="${SCRIPT_DIR}/faults"
ROOT_DIR="${SCRIPT_DIR}/../../"
ROOT_SCRIPTS_DIR="${ROOT_DIR}/scripts/"
BINFILE="${SCRIPT_DIR}/dataframe/build/bin/main"

mkdir -p ${FAULT_DIR}

# SCRIPT
# bash run.sh --nopie --kona -d=nopie -f

# DATA
# exp=run-09-21-12-26-23
# exp=run-10-18-23-27-02
exp=run-10-20-14-33-19

# locate fault samples
expdir=${DATADIR}/$exp
kfaultsin=${expdir}/kona_fault_samples.out
if [ ! -f ${kfaultsin} ]; then 
    echo "kona_fault_samples.out not found for ${app} at ${expdir}"
    exit 1
fi

if [ ! -f ${BINFILE} ]; then 
    echo "binary not found at ${binfile}"
    exit 1
fi

python3 ${ROOT_SCRIPTS_DIR}/parse_kona_faults.py -i ${kfaultsin} -b ${BINFILE}  \
    | column -s, -t > ${FAULT_DIR}/${exp}.txt