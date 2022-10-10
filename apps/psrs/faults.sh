#
# Output fault locations
#

SCRIPT_PATH=`realpath $0`
SCRIPT_DIR=`dirname ${SCRIPT_PATH}`
DATADIR="${SCRIPT_DIR}/data"
FAULT_DIR="${SCRIPT_DIR}/faults"
ROOT_DIR="${SCRIPT_DIR}/../../"
ROOT_SCRIPTS_DIR="${ROOT_DIR}/scripts/"
BINFILE="main.out"

mkdir -p ${FAULT_DIR}

# SCRIPT
# Takes ~20 mins
# bash run.sh -c=1 -t=1 -nk=1024000000 --nopie --kona --tag=pthreads -d=nopie -fl="-DCUSTOM_QSORT" -lm=1000000000 -f

# DATA
# exp=run-09-21-14-15-44
# exp=run-10-07-10-28-24
exp=run-10-07-12-06-29

# locate fault samples
expdir=${DATADIR}/saved/$exp
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