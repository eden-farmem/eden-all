PLOTEXT=pdf

for f in `ls run*/stats/stat.csv`; do 
# for f in `ls run.20210805082856-shenango-memcached-tcp/stats/stat.csv`; do 
    dir1=`dirname $f`; 
    dir=`dirname $dir1`; 
    mpps=`jq ".clients[] | .[0].start_mpps" $dir/config.json | paste -sd+ | bc`
    echo $dir, $mpps
    cat $f
    
    # plotname=$dir/plot_p99.$PLOTEXT
    # python3 tools/plot.py -d $f \
    #     -xc achieved -xl "Xput (Mpps)" --xmul 1e-6              \
    #     -yc p99 -yl "Latency (micro-sec)" --ymin 0 --ymax 500   \
    #     -of $PLOTEXT -o $plotname -s
    # gv $plotname &

    shortid=`echo $dir | cut -b12-18`
    plots="$plots -dyc $f p99 -l $shortid,$mpps "
done

# echo $plots
# plotname=plots_p99.$PLOTEXT
# python3 tools/plot.py $plots \
#     -xc achieved -xl "Xput (Mpps)" --xmul 1e-6      \
#     -yl "Latency (micro-sec)" --ymin 0 --ymax 500   \
#     -of $PLOTEXT -o $plotname -s
# gv $plotname &


