#
# Plots for the paper
#

PLOTEXT=pdf
SCRIPT_PATH=`realpath $0`
SCRIPT_DIR=`dirname ${SCRIPT_PATH}`
ROOTDIR="${SCRIPT_DIR}/../../"
ROOT_SCRIPTS_DIR="${ROOTDIR}/scripts/"
PLOTDIR=${SCRIPT_DIR}/plots/paper/
DATADIR=${SCRIPT_DIR}/data

usage="\n
-id,  --plotid \t pick one of the many charts this script can generate\n
-h, --help \t\t this usage information message\n"

for i in "$@"
do
case $i in
    -id=*|--fig=*|--plotid=*)
    PLOTID="${i#*=}"
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

mkdir -p $PLOTDIR

# Plot 1: UFFD Fault path
# Data: bash plot.sh -id=5
if [ "$PLOTID" == "1" ]; then
    plotname=${PLOTDIR}/uffd_vectoring.${PLOTEXT}
    python3 ${ROOT_SCRIPTS_DIR}/plot.py -yc "xput"     \
        -d ${DATADIR}/fault_path_one_fd_hthr_1_pti_off.dat      -l "1"  -ls solid   -cmi 0  \
        -d ${DATADIR}/fault_path_fd_per_core_hthr_1_pti_off.dat -l ""   -ls dashed  -cmi 1  \
        -d ${DATADIR}/fault_path_one_fd_hthr_2_pti_off.dat      -l "2"  -ls solid   -cmi 0  \
        -d ${DATADIR}/fault_path_fd_per_core_hthr_2_pti_off.dat -l ""   -ls dashed  -cmi 1  \
        -d ${DATADIR}/fault_path_one_fd_hthr_4_pti_off.dat      -l "4"  -ls solid   -cmi 0  \
        -d ${DATADIR}/fault_path_fd_per_core_hthr_4_pti_off.dat -l ""   -ls dashed  -cmi 1  \
        -yl "MOPS" --ymul 1e-6 --ymin 0 --ymax 1.5  -xc cores -xl "CPU Cores"               \
        --size 5 3.5 -fs 15 -of $PLOTEXT -o $plotname -lt "Handler Cores"
    display ${plotname} &
fi

# Plot 2: UFFD Ops
# Data: bash plot.sh -id=1
# Data: bash plot.sh -id=2
# Data: bash plot.sh -id=3
if [ "$PLOTID" == "2" ]; then
    plotname=${PLOTDIR}/uffd_ops.${PLOTEXT}
    python3 ${ROOT_SCRIPTS_DIR}/plot.py -yc "xput"     \
        -d ${DATADIR}/uffd_copy_one_fd_reg_pti_off.dat          -l "Add"    -ls solid   -cmi 0  \
        -d ${DATADIR}/uffd_copy_one_fd_reg_pti_on.dat           -l ""       -ls dashed  -cmi 1  \
        -d ${DATADIR}/madv_dneed_one_fd_reg_pti_off.dat         -l "Remove" -ls solid   -cmi 0  \
        -d ${DATADIR}/madv_dneed_one_fd_reg_pti_on.dat          -l ""       -ls dashed  -cmi 1  \
        -d ${DATADIR}/uffd_prot_one_fd_reg_pti_off.dat          -l "Protect" -ls solid   -cmi 0 \
        -d ${DATADIR}/uffd_prot_one_fd_reg_pti_on.dat           -l ""       -ls dashed  -cmi 1  \
        -yl "MOPS" --ymul 1e-6 --ymin 0 --ymax 3 -xc cores -xl "CPU Cores"                      \
        --size 5 3.5 -fs 15 -of $PLOTEXT -o $plotname -lt "UFFD Page Op"
    display ${plotname} &
fi

# Plot 3: UFFD Ops Latency
# Data: bash plot.sh -id=1
# Data: bash plot.sh -id=2
# Data: bash plot.sh -id=3
if [ "$PLOTID" == "3" ]; then
    config=one_fd_reg
    latdatapfx=uffd_ops_latency_pti_
    for PTI in "on" "off"; do
        latdata=${DATADIR}/${latdatapfx}${PTI}.dat
        echo "op,latns" > $latdata
        for op in "uffd_copy" "madv_dneed" "uffd_prot"; do
            case $op in
            "uffd_copy")    opname="Add";;
            "madv_dneed")   opname="Remove";;
            "uffd_prot")    opname="Protect";;
            *)              echo "Unknown op"; exit;;
            esac
            datafile=${DATADIR}/${op}_${config}_pti_${PTI}.dat
            row2col4=`sed -n '2p' ${datafile}  2>/dev/null | awk -F, '{ print $4 }'`
            echo "$opname,$row2col4" >> $latdata
        done
        cat $latdata
    done

    plotname=${PLOTDIR}/uffd_ops_latency.${PLOTEXT}
    python3 ${ROOT_SCRIPTS_DIR}/plot.py -z bar -bw 0.1          \
        -d ${DATADIR}/${latdatapfx}off.dat  -l "Off" -bhs "/"   \
        -d ${DATADIR}/${latdatapfx}on.dat   -l "On"  -bhs "\\"  \
        -yc "latns" -yl "Cost (µs)" --ymul 1e-3 -xc op -xl "UFFD Page Op" \
        --size 5 3.5 -fs 15 -of $PLOTEXT -o $plotname -lt "PTI" 
    display ${plotname} &
fi

# Plot 4: UFFD Vectored Write Protect
# Data: bash plot.sh -id=10
if [ "$PLOTID" == "4" ]; then
    plotname=${PLOTDIR}/uffd_protect_batched.${PLOTEXT}
    python3 ${ROOT_SCRIPTS_DIR}/plot.py -yc "xput"     \
        -d ${DATADIR}/uffd_wp_vec_batch_1_pti_off.dat   -l "1"  \
        -d ${DATADIR}/uffd_wp_vec_batch_2_pti_off.dat   -l "2"  \
        -d ${DATADIR}/uffd_wp_vec_batch_4_pti_off.dat   -l "4"  \
        -d ${DATADIR}/uffd_wp_vec_batch_8_pti_off.dat   -l "8"  \
        -yl "MOPS" --ymul 1e-6 --ymin 0 --ymax 10  -xc cores -xl "CPU Cores"   \
        --size 5 3.5 -fs 15 -of $PLOTEXT -o $plotname -lt "Batch Size"
    display ${plotname} &
fi

# Plot 5: UFFD Vectored Remove
# Data: bash plot.sh -id=9
if [ "$PLOTID" == "5" ]; then
    plotname=${PLOTDIR}/uffd_remove_batched.${PLOTEXT}
    python3 ${ROOT_SCRIPTS_DIR}/plot.py -yc "xput"              \
        -d ${DATADIR}/proc_madv_batch_1_pti_off.dat   -l "1"   \
        -d ${DATADIR}/proc_madv_batch_2_pti_off.dat   -l "2"   \
        -d ${DATADIR}/proc_madv_batch_4_pti_off.dat   -l "4"   \
        -d ${DATADIR}/proc_madv_batch_8_pti_off.dat   -l "8"   \
        -yl "MOPS" --ymul 1e-6 --ymin 0 --ymax 5  -xc cores -xl "CPU Cores"    \
        --size 5 3.5 -fs 15 -of $PLOTEXT -o $plotname -lt "Batch Size"
    display ${plotname} &
fi

# Plot 6: UFFD Batched Ops Latency
# Data: bash plot.sh -id=1
if [ "$PLOTID" == "6" ]; then
    PTI=off
    latdatasfx=latency_pti_${PTI}
    for op in "uffd_wp_vec" "proc_madv"; do
        case $op in
        "uffd_wp_vec")      opname="Protect";;
        "proc_madv")        opname="Remove";;
        *)                  echo "Unknown op"; exit;;
        esac
        latdata=${DATADIR}/${op}_${latdatasfx}.dat
        echo "batchsz,latns" > $latdata
        for batch in 1 2 4 8 16 32; do
            datafile=${DATADIR}/${op}_batch_${batch}_pti_${PTI}.dat
            cat $datafile
            row2col4=`sed -n '2p' ${datafile}  2>/dev/null | awk -F, '{ print $4 }'`
            echo "$batch,$row2col4" >> $latdata
        done
        cat $latdata
    done

    plotname=${PLOTDIR}/uffd_batched_latency.${PLOTEXT}
    python3 ${ROOT_SCRIPTS_DIR}/plot.py -z bar -bw 0.1                          \
        -d ${DATADIR}/uffd_wp_vec_${latdatasfx}.dat     -l "Protect" -bhs "/"   \
        -d ${DATADIR}/proc_madv_${latdatasfx}.dat       -l "Remove"  -bhs "\\"  \
        -yc "latns" -yl "Cost (µs)" --ymul 1e-3 -xc batchsz -xl "Batch Size"    \
        --size 5 3.5 -fs 15 -of $PLOTEXT -o $plotname -lt "UFFD Page Op" 
    display ${plotname} &
fi

# Plot 7: For Paper
if [ "$PLOTID" == "7" ]; then
    plotname=${PLOTDIR}/uffd_scalability.${PLOTEXT}
    python3 ${ROOT_SCRIPTS_DIR}/plot.py -yc "xput"                                                          \
        -d ${DATADIR}/fault_path_one_fd_hthr_4_pti_off.dat   		
        -d ${DATADIR}/uffd_copy_one_fd_reg_pti_off.dat       		
        -d ${DATADIR}/madv_dneed_one_fd_reg_pti_off.dat      		
        -d ${DATADIR}/uffd_prot_one_fd_reg_pti_on.dat        		
        -yl "MOPS" --ymul 1e-6 --ymin 0 --ymax 4  -xc cores -xl "CPU Cores"                               \
        --size 5 3.5 -fs 15 -of $PLOTEXT -o $plotname
    display ${plotname} &
fi

# Plot 8: No plot, just move all uffd data for Stew
if [ "$PLOTID" == "8" ]; then
    # uffd figure (fig 1)
    DSTDIR=../../../faults-analysis/paper/uffd
    cp ${DATADIR}/fault_path_one_fd_hthr_4_pti_off.dat  ${DSTDIR}/uffd_zero_page_faults.dat  
    cp ${DATADIR}/uffd_copy_one_fd_reg_pti_off.dat      ${DSTDIR}/uffd_map_page.dat
    cp ${DATADIR}/madv_dneed_one_fd_reg_pti_off.dat     ${DSTDIR}/uffd_remove_page.dat
    cp ${DATADIR}/uffd_prot_one_fd_reg_pti_on.dat       ${DSTDIR}/uffd_write_protect.dat

    # uffd batching ops figure (a)
    DSTDIR=../../../faults-analysis/paper/uffd-batching
    cp ${DATADIR}/uffd_wp_vec_batch_1_pti_off.dat   ${DSTDIR}/uffd_wp_vec_batch_1.dat
    cp ${DATADIR}/uffd_wp_vec_batch_2_pti_off.dat	${DSTDIR}/uffd_wp_vec_batch_2.dat
    cp ${DATADIR}/uffd_wp_vec_batch_4_pti_off.dat	${DSTDIR}/uffd_wp_vec_batch_4.dat	
    cp ${DATADIR}/uffd_wp_vec_batch_8_pti_off.dat	${DSTDIR}/uffd_wp_vec_batch_8.dat
    cp ${DATADIR}/uffd_wp_vec_batch_8_pti_off.dat	${DSTDIR}/uffd_wp_vec_batch_16.dat
    cp ${DATADIR}/uffd_wp_vec_batch_8_pti_off.dat	${DSTDIR}/uffd_wp_vec_batch_32.dat

    # uffd batching ops figure (b)
    cp ${DATADIR}/proc_madv_batch_1_pti_off.dat		${DSTDIR}/uffd_madv_batch_1.dat  
    cp ${DATADIR}/proc_madv_batch_2_pti_off.dat		${DSTDIR}/uffd_madv_batch_2.dat
    cp ${DATADIR}/proc_madv_batch_4_pti_off.dat		${DSTDIR}/uffd_madv_batch_4.dat
    cp ${DATADIR}/proc_madv_batch_8_pti_off.dat		${DSTDIR}/uffd_madv_batch_8.dat
    cp ${DATADIR}/proc_madv_batch_16_pti_off.dat    ${DSTDIR}/uffd_madv_batch_16.dat
    cp ${DATADIR}/proc_madv_batch_32_pti_off.dat    ${DSTDIR}/uffd_madv_batch_32.dat

    # uffd batching latency figure (c)
    cp ${DATADIR}/uffd_wp_vec_latency_pti_off.dat  	${DSTDIR}/uffd_wp_vec_latency.dat
    cp ${DATADIR}/proc_madv_latency_pti_off.dat     ${DSTDIR}/uffd_madv_latency.dat
fi