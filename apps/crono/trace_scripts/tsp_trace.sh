#we need to run from this directory, as long as we do that everyting is going to be gravy
source ../trace-lib.sh "$@"

echo "Starting Traveling Salesman"
../tsp 1 15
export -n LD_PRELOAD

finish_exp