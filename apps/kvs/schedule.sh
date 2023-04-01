
## native
APPS='rocksdb
leveldb
memcached
redis'


#Defaults
SCRIPT_PATH=`realpath $0`
SCRIPTDIR=`dirname ${SCRIPT_PATH}`
ROOTDIR="${SCRIPTDIR}/../../"
ROOT_SCRIPTS_DIR="${ROOTDIR}/scripts/"

source ${ROOT_SCRIPTS_DIR}/utils.sh

for app in `echo ${APPS}`; do
    echo $app

    ### run
    # pushd ${app}
    # nohup bash schedule.sh &> out &
    # popd

    ### show
    pushd ${app}
    bash show.sh
    popd

    ### plot
    # bash plot.sh -id=6 -a=$app &> plot_$app &
done
