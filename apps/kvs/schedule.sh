
## native
APPS='rocksdb
leveldb
redis
memcached'

for app in `echo ${APPS}`; do
    echo $app

    ### plot
    bash plot.sh -id=6 -a=$app &> plot_$app &
done
