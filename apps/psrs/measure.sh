#!/bin/bash
set -e

#
# Run sort benchmark in various settings
# 

usage="\n
-f, --force \t\t force re-run experiments\n
-d, --debug \t\t build debug\n
-h, --help \t\t this usage information message\n"

#Defaults
SCRIPT_DIR=`dirname "$0"`
TMP_PFX=tmp_sort
WARMUP=1

# parse cli
for i in "$@"
do
case $i in
    -d|--debug)
    CFLAGS="$CFLAGS -DDEBUG"
    ;;

    -f|--force)
    FORCE=1
    ;;

    -h | --help)
    echo -e $usage
    exit
    ;;

    *)                      # unknown option
    echo "Unkown Option: $i"
    echo -e $usage
    exit
    ;;
esac
done

# settings
NKEYS=16000000      # ? GB
lmem=1000000000     # 1 GB
cores=1
thr=1

# create a stop button
touch __running__
check_for_stop() {
    # stop if the fd is removed
    if [ ! -f __running__ ]; then 
        echo "stop requested"   
        exit 0
    fi
}

desc="withkona"
# for sflag in "" "--shenango"; do
for kflag in "--kona"; do     #"--kona"
	# for nkeys_ in 16 32 64 128 256 512 1024 2048 4096; do
	for nkeys_ in 512; do
		nkeys=$((nkeys_*1000000))
		for cores in 8 12; do
			# for tpc in 1 2 4 8 16; do
			for tpc in 1; do
                check_for_stop
				thr=$((cores*tpc))
				echo "Running ${cores} cores, ${thr} threads, ${nkeys} keys"
				bash run.sh -c=${cores} -t=${thr} -nk=${nkeys} ${sflag} ${kflag} -d="""${desc}"""
			done
		done
	done
done

# cleanup
rm -f ${TMP_PFX}*
rm -f __running__