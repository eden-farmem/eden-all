#we need to run from this directory, as long as we do that everyting is going to be gravy
BINARY=`realpath ./sssp`
SOURCE_DIR=`realpath ./`

# parse cli
for i in "$@"
do
case $i in
    # used for getting the binary when running an analysis script
    -b|--binary)
        echo ${BINARY}
        exit
    ;;
    #used for cloc
    -s|--source)
        echo ${SOURCE_DIR}
        exit
    ;;
esac
done

#we need to run from this directory, as long as we do that everyting is going to be gravy
source ../trace-lib.sh "$@"

echo "Starting Single Source Shortest Path"
${BINARY} 0 1 16384 16
export -n LD_PRELOAD

finish_exp