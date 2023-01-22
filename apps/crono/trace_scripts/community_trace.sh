#we need to run from this directory, as long as we do that everyting is going to be gravy
source ../trace-lib.sh "$@"

echo "Starting Community detection"
../community_lock 1 1 1 ../../../web-Google.txt
export -n LD_PRELOAD

finish_exp