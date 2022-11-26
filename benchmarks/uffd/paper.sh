#
# Plots for the paper
#

PLOTEXT=pdf
SCRIPT_PATH=`realpath $0`
SCRIPT_DIR=`dirname ${SCRIPT_PATH}`
ROOTDIR="${SCRIPT_DIR}/../../"
ROOT_SCRIPTS_DIR="${ROOTDIR}/scripts/"
PLOTDIR=${SCRIPT_DIR}/plots
DATADIR=${SCRIPT_DIR}/data


# # Plot 1: UFFD Fault path
# # Data: bash plot.sh -id=5
# plotname=${PLOTDIR}/uffd_vectoring.${PLOTEXT}
# python3 ${ROOT_SCRIPTS_DIR}/plot.py -yc "xput"     \
#     -d ${DATADIR}/fault_path_one_fd_hthr_1_pti_off.dat      -l "1"  -ls solid   -cmi 0  \
#     -d ${DATADIR}/fault_path_fd_per_core_hthr_1_pti_off.dat -l ""   -ls dashed  -cmi 1  \
#     -d ${DATADIR}/fault_path_one_fd_hthr_2_pti_off.dat      -l "2"  -ls solid   -cmi 0  \
#     -d ${DATADIR}/fault_path_fd_per_core_hthr_2_pti_off.dat -l ""   -ls dashed  -cmi 1  \
#     -d ${DATADIR}/fault_path_one_fd_hthr_4_pti_off.dat      -l "4"  -ls solid   -cmi 0  \
#     -d ${DATADIR}/fault_path_fd_per_core_hthr_4_pti_off.dat -l ""   -ls dashed  -cmi 1  \
#     -yl "MOPS" --ymul 1e-6 --ymin 0 --ymax 1.5  -xc cores -xl "CPU Cores"               \
#     --size 5 3.5 -fs 15 -of $PLOTEXT -o $plotname -lt "Handler Cores"
# display ${plotname} &

# # Plot 2: UFFD Ops
# # Data: bash plot.sh -id=1
# # Data: bash plot.sh -id=2
# # Data: bash plot.sh -id=3
# plotname=${PLOTDIR}/uffd_ops.${PLOTEXT}
# python3 ${ROOT_SCRIPTS_DIR}/plot.py -yc "xput"     \
#     -d ${DATADIR}/uffd_copy_one_fd_reg_pti_off.dat          -l "Add"    -ls solid   -cmi 0  \
#     -d ${DATADIR}/uffd_copy_one_fd_reg_pti_on.dat           -l ""       -ls dashed  -cmi 1  \
#     -d ${DATADIR}/madv_dneed_one_fd_reg_pti_off.dat         -l "Remove" -ls solid   -cmi 0  \
#     -d ${DATADIR}/madv_dneed_one_fd_reg_pti_on.dat          -l ""       -ls dashed  -cmi 1  \
#     -d ${DATADIR}/uffd_prot_one_fd_reg_pti_off.dat          -l "Protect" -ls solid   -cmi 0 \
#     -d ${DATADIR}/uffd_prot_one_fd_reg_pti_on.dat           -l ""       -ls dashed  -cmi 1  \
#     -yl "MOPS" --ymul 1e-6 --ymin 0 --ymax 3 -xc cores -xl "CPU Cores"                      \
#     --size 5 3.5 -fs 15 -of $PLOTEXT -o $plotname -lt "UFFD Page Op"
# display ${plotname} &

# Plot 2: UFFD Ops Latency
# Data: bash plot.sh -id=1
# Data: bash plot.sh -id=2
# Data: bash plot.sh -id=3
plots=
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
    plots="$plots -d $latdata -l $PTI"
    cat $latdata
done
echo $plots

plotname=${PLOTDIR}/uffd_ops_latency.${PLOTEXT}
python3 ${ROOT_SCRIPTS_DIR}/plot.py -z bar -bw 0.1          \
    -d ${DATADIR}/${latdatapfx}off.dat  -l "Off" -bhs "/"   \
    -d ${DATADIR}/${latdatapfx}on.dat   -l "On"  -bhs "\\"  \
    -yc "latns" -yl "µs" --ymul 1e-3 -xc op -xl "UFFD Page Op" \
    --size 5 3.5 -fs 15 -of $PLOTEXT -o $plotname -lt "PTI" 
display ${plotname} &