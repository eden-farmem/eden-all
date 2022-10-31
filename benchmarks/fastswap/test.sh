
#
# Test concurrent app faults code path in Kona
#

usage="\n
-d, --debug \t\t build debug\n
-h, --help \t\t this usage information message\n"

READ_OP=0
WRITE_OP=1
RANDOM_OP=2

# parse cli
for i in "$@"
do
case $i in
    -d|--debug)
    DEBUG="--debug"
    ;;

    -h | --help)
    echo -e $usage
    exit
    ;;

    *)                      # unknown option
    echo "Unknown Option: $i"
    echo -e $usage
    exit
    ;;
esac
done

bash run.sh -d="test" --cflags="-DFAULT_OP=${WRITE_OP}" \
    --thr=1 --mem=2000000000 ${DEBUG}