#we need to run from this directory, as long as we do that everyting is going to be gravy
BINARY=`realpath ./community_lock`
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


source ../trace-lib.sh "$@"

echo "Starting Community detection"
${BINARY} 1 4 1 ../../../web-Google.txt
export -n LD_PRELOAD

finish_exp