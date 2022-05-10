
#
# Test concurrent app faults code path in Kona
#

usage="\n
-d, --debug \t\t build debug\n
-h, --help \t\t this usage information message\n"

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
    echo "Unkown Option: $i"
    echo -e $usage
    exit
    ;;
esac
done

RANDOM_OP=2
bash run.sh \
    --cflags="-DUSE_APP_FAULTS -DFAULT_OP=${RANDOM_OP} -DCONCURRENT" \
    --kcflags="-DNO_ZEROPAGE_OPT"   \
    --threads=8  --safemode --force ${DEBUG}