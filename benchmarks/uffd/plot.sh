#!/bin/bash
set -e

#
# Plot figures for the paper
#

PLOTEXT=png
SCRIPT_DIR=`dirname "$0"`
PLOTSRC=${SCRIPT_DIR}/../../scripts/plot.py
PLOTDIR=${SCRIPT_DIR}/plots
DATADIR=${SCRIPT_DIR}/data
TMP_FILE_PFX='tmp_uffd_'
PTI=on

usage="\n
-f,   --force \t\t force re-summarize data and re-generate plots\n
-fp,  --force-plots \t force re-generate just the plots\n
-id,  --plotid \t pick one of the many charts this script can generate\n
-l,  --lat \t also plot latency numbers\n
-d,  --debug \t run programs in debug mode where applies\n
-h, --help \t\t this usage information message\n"

for i in "$@"
do
case $i in
    -f|--force)
    FORCE=1
    FORCE_PLOTS=1
    ;;
    
    -fp|--force-plots)
    FORCE_PLOTS=1
    ;;

    -np|--no-plots)
    NO_PLOTS=1
    ;;

    -id=*|--fig=*|--plotid=*)
    PLOTID="${i#*=}"
    ;;

    -l|--lat)
    LATPLOT=1
    ;;
    
    -d|--debug)
    DEBUG=1
    DEBUG_FLAG="-DDEBUG"
    ;;

    *)          # unknown option
    echo "Unknown Option: $i"
    echo -e $usage
    exit
    ;;
esac
done

# point to last chart if not provided
if [ -z "$PLOTID" ]; then 
    PLOTID=`grep '"$PLOTID" == "."' $0 | wc -l`
    PLOTID=$((PLOTID-1))
fi

# PTI status
pti_msg=$(sudo dmesg | grep 'page tables isolation: enabled' || true)
if [ -z "$pti_msg" ]; then
    PTI=off
fi
echo "PTI status: $PTI"

# setup
mkdir -p $PLOTDIR
mkdir -p $DATADIR
LS=solid
CMI=1

# gets data and fills $plots
add_data_to_plot() {
    group=$1
    label=$2
    cflags=$3
    share_uffd=$4
    hthr=$5

    if [ "$share_uffd" == "1" ]; then  sflag="";            fi
    if [ "$share_uffd" == "0" ]; then  sflag="--nosharefd"; fi

    datafile=${DATADIR}/${group}_${label}_pti_${PTI}.dat
    if [[ $FORCE ]] || [ ! -f "$datafile" ]; then
        echo "cores,xput,errors,latns,memgb" > $datafile
        for cores in 1 2 3 4 5 6 7 8; do
            if [[ $hthr ]]; then
                if [ "$hthr" == "EQUAL" ]; then     hflag="-th=${cores}";
                else    hflag="-th=${hthr}";    fi
            fi
            bash ${SCRIPT_DIR}/run.sh -t=$cores ${sflag} ${hflag} \
                -o="$cflags" -of=${datafile}
        done
    fi
    cat $datafile
    plots="$plots -d $datafile -l $label -ls $LS -cmi $CMI"

    # gather latency numbers
    if [ ! -f $latfile ]; then  echo "config,latns" > $latfile; fi
    row2col3=`sed -n '2p' ${datafile} | awk -F, '{ print $4 }'`
    echo "$label,$row2col3" >> $latfile
}

# plots from $plots
generate_xput_plot() {
    group=$1
    ymax=$2
    if [[ $ymax ]]; then ylflag="--ymin 0 --ymax ${ymax}"; fi
    if [[ $NO_PLOTS ]]; then return; fi

    plotname=${PLOTDIR}/${group}_pti_${PTI}_xput.${PLOTEXT}
    if [[ $FORCE_PLOTS ]] || [ ! -f "$plotname" ]; then
        python ${PLOTSRC} ${plots} ${ylflag}    \
            -yc xput -yl "MOPS" --ymul 1e-6     \
            -xc cores -xl "Cores"               \
            --size 5 4 -fs 11 -of ${PLOTEXT} -o $plotname
    fi
    display $plotname &
}

plots=
latfile=${TMP_FILE_PFX}latency
rm -f $latfile

## benchmark UFFD copy
if [ "$PLOTID" == "1" ]; then
    YMAX=3.5
    add_data_to_plot "uffd_copy" "one_fd"            "-DMAP_PAGE"                           1
    add_data_to_plot "uffd_copy" "one_fd_reg"        "-DMAP_PAGE -DSHARE_REGION"            1
    add_data_to_plot "uffd_copy" "one_fd_reg_nowake" "-DMAP_PAGE_NOWAKE -DSHARE_REGION"     1
    add_data_to_plot "uffd_copy" "fd_per_core"       "-DMAP_PAGE"                           0
    generate_xput_plot "uffd_copy" ${YMAX}
fi

## benchmark Madvise
if [ "$PLOTID" == "2" ]; then
    YMAX=1.5
    add_data_to_plot "madv_dneed" "one_fd"          "-DUNMAP_PAGE"                  1
    add_data_to_plot "madv_dneed" "one_fd_reg"      "-DUNMAP_PAGE -DSHARE_REGION"   1
    add_data_to_plot "madv_dneed" "fd_per_core"     "-DUNMAP_PAGE"                  0
    generate_xput_plot "madv_dneed" ${YMAX}
fi

## benchmark UFFD WP Add
if [ "$PLOTID" == "3" ]; then
    YMAX=1.5
    add_data_to_plot "uffd_prot" "one_fd"        "-DPROTECT_PAGE"                    1
    add_data_to_plot "uffd_prot" "one_fd_reg"    "-DPROTECT_PAGE -DSHARE_REGION"     1
    add_data_to_plot "uffd_prot" "fd_per_core"   "-DPROTECT_PAGE"                    0
    generate_xput_plot "uffd_prot" ${YMAX}
fi

## benchmark UFFD WP Remove
if [ "$PLOTID" == "4" ]; then
    YMAX=1.5
    add_data_to_plot "uffd_unprot" "one_fd"             "-DUNPROTECT_PAGE"                          1
    add_data_to_plot "uffd_unprot" "one_fd_reg"         "-DUNPROTECT_PAGE -DSHARE_REGION"           1
    add_data_to_plot "uffd_unprot" "one_fd_reg_nowake"  "-DUNPROTECT_PAGE_NOWAKE -DSHARE_REGION"    1
    add_data_to_plot "uffd_unprot" "fd_per_core"        "-DUNPROTECT_PAGE"                          0
    generate_xput_plot "uffd_unprot" ${YMAX}
fi

## benchmark entire fault path
if [ "$PLOTID" == "5" ]; then
    plots=
    sharefd=1
    YMAX=1.5
    for hthr in 8; do 
        add_data_to_plot "fault_path_one_fd" "hthr_$hthr" "-DACCESS_PAGE" $sharefd $hthr
    done
    generate_xput_plot "fault_path_one_fd"     ${YMAX}

    plots=
    sharefd=0
    for hthr in 8; do 
        add_data_to_plot "fault_path_fd_per_core" "hthr_$hthr" "-DACCESS_PAGE" $sharefd $hthr
    done
    generate_xput_plot "fault_path_fd_per_core" ${YMAX}
fi

## benchmark entire fault path with/without hyperthreading handlers
if [ "$PLOTID" == "6" ]; then
    plots=
    sharefd=0
    YMAX=1.5
    # add_data_to_plot "fault_path_ht_eff" "noht"  "-DACCESS_PAGE"                  $sharefd "EQUAL"
    # add_data_to_plot "fault_path_ht_eff" "ht"    "-DACCESS_PAGE -DHT_HANDLERS"    $sharefd "EQUAL"
    add_data_to_plot "fault_path_ht_eff" "noht-page"    "-DACCESS_PAGE_WHOLE"       $sharefd "EQUAL"
    add_data_to_plot "fault_path_ht_eff" "ht-page"      "-DACCESS_PAGE_WHOLE -DHT_HANDLERS"   $sharefd "EQUAL"
    generate_xput_plot "fault_path_ht_eff" ${YMAX}
fi

## collect xputs for all configs 
## (assumes data is already collected for both PTI on/off)
if [ "$PLOTID" == "7" ]; then
    plots=
    config=one_fd_reg
    for op in "uffd_copy" "madv_dneed" "uffd_prot" "uffd_unprot"; do
        for PTI in "on" "off"; do
            LS=dashed; CMI=0;
            if [ "$PTI" == "off" ]; then    LS=solid;    CMI=1;  fi
            datafile=${DATADIR}/${op}_${config}_pti_${PTI}.dat
            plots="$plots -d $datafile -l $op($PTI) -ls $LS -cmi $CMI"
        done
    done
    PTI=both
    generate_xput_plot "all_ops" 3.5
fi

## collect latencies for all configs 
## (assumes data is already collected for both PTI on/off)
if [ "$PLOTID" == "8" ]; then
    plots=
    config=one_fd_reg
    for PTI in "on" "off"; do
        latdata=${TMP_FILE_PFX}${config}_${PTI}_latdata
        rm -f $latdata
        echo "op,latns" > $latdata
        for op in "uffd_copy" "madv_dneed" "uffd_prot" "uffd_unprot"; do
            datafile=${DATADIR}/${op}_${config}_pti_${PTI}.dat
            row2col4=`sed -n '2p' ${datafile}  2>/dev/null | awk -F, '{ print $4 }'`
            echo "$op,$row2col4" >> $latdata
        done
        plots="$plots -d $latdata -l $PTI"
    done

    if [ -z "$NO_PLOTS" ]; then
        plotname=${PLOTDIR}/latency.${PLOTEXT}
        if [[ $FORCE_PLOTS ]] || [ ! -f "$plotname" ]; then
            python3 ${PLOTSRC} ${plots}  -z bar -bw 0.1     \
                -yc latns -yl "Cost (µs)" --ymul 1e-3       \
                --ymax 4 -xc op -xl "Operation" -lt "PTI"   \
                --size 5 3 -fs 11 -of ${PLOTEXT} -o $plotname
        fi
        display $plotname &
    fi
fi

## benchmark Madvise batching (with single fd, single region)
if [ "$PLOTID" == "9" ]; then
    YMAX=10
    LS=dashed; CMI=0;
    add_data_to_plot "madv" "no_batch"       "-DUNMAP_PAGE -DSHARE_REGION -DBATCH_SIZE=1"        1
    LS=solid; CMI=1;
    add_data_to_plot "proc_madv" "batch_1"  "-DUNMAP_PAGE_VEC -DSHARE_REGION -DBATCH_SIZE=1"    1
    # LS=dashed; CMI=0;
    # add_data_to_plot "madv" "batch_2"       "-DUNMAP_PAGE -DSHARE_REGION -DBATCH_SIZE=2"        1
    LS=solid; CMI=1;
    add_data_to_plot "proc_madv" "batch_2"  "-DUNMAP_PAGE_VEC -DSHARE_REGION -DBATCH_SIZE=2"    1
    # LS=dashed; CMI=0;
    # add_data_to_plot "madv" "batch_4"       "-DUNMAP_PAGE -DSHARE_REGION -DBATCH_SIZE=4"        1
    LS=solid; CMI=1;
    add_data_to_plot "proc_madv" "batch_4"  "-DUNMAP_PAGE_VEC -DSHARE_REGION -DBATCH_SIZE=4"    1
    # LS=dashed; CMI=0;
    # add_data_to_plot "madv" "batch_8"       "-DUNMAP_PAGE -DSHARE_REGION -DBATCH_SIZE=8"        1
    LS=solid; CMI=1;
    add_data_to_plot "proc_madv" "batch_8"  "-DUNMAP_PAGE_VEC -DSHARE_REGION -DBATCH_SIZE=8"    1
    generate_xput_plot "madv_batching" ${YMAX}
fi

## benchmark UFFD WP batching (with single fd, single region)
if [ "$PLOTID" == "10" ]; then
    YMAX=10
    LS=dashed; CMI=0;
    add_data_to_plot "uffd_wp" "no_vec"      "-DPROTECT_PAGE -DSHARE_REGION -DBATCH_SIZE=1"        1
    LS=solid; CMI=1;
    add_data_to_plot "uffd_wp_vec" "batch_1"  "-DPROTECT_PAGE_VEC -DSHARE_REGION -DBATCH_SIZE=1"    1
    # LS=dashed; CMI=0;
    # add_data_to_plot "uffd_wp" "batch_2"      "-DPROTECT_PAGE -DSHARE_REGION -DBATCH_SIZE=2"        1
    LS=solid; CMI=1;
    add_data_to_plot "uffd_wp_vec" "batch_2"  "-DPROTECT_PAGE_VEC -DSHARE_REGION -DBATCH_SIZE=2"    1
    # LS=dashed; CMI=0;
    # add_data_to_plot "uffd_wp" "batch_4"      "-DPROTECT_PAGE -DSHARE_REGION -DBATCH_SIZE=4"        1
    LS=solid; CMI=1;
    add_data_to_plot "uffd_wp_vec" "batch_4"  "-DPROTECT_PAGE_VEC -DSHARE_REGION -DBATCH_SIZE=4"    1
    # LS=dashed; CMI=0;
    # add_data_to_plot "uffd_wp" "batch_8"      "-DPROTECT_PAGE -DSHARE_REGION -DBATCH_SIZE=8"        1
    LS=solid; CMI=1;
    add_data_to_plot "uffd_wp_vec" "batch_8"  "-DPROTECT_PAGE_VEC -DSHARE_REGION -DBATCH_SIZE=8"    1
    generate_xput_plot "uffd_wp_batching" ${YMAX}
fi

## bench

# cleanup
rm -f ${TMP_FILE_PFX}*