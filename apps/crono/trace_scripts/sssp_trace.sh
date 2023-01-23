#we need to run from this directory, as long as we do that everyting is going to be gravy
source ../trace-lib.sh "$@"

echo "Starting Single Source Shortest Path"
../sssp 0 1 16384 16
export -n LD_PRELOAD

finish_exp