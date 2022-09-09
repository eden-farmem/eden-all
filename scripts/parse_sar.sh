#!/bin/bash
set -e 
#
# Parse sar files
#

SCRIPT_DIR=`dirname "$0"`
<<<<<<< Updated upstream
=======
DATADIR=${SCRIPT_DIR}/data
>>>>>>> Stashed changes
SAREXT=".sar"
SAR_HEADER_ROW=3
START=0
END=5000000000

usage="\n
<<<<<<< Updated upstream
-sf, --sarfile \t path to the sar-outputted data file\n
=======
-n, --name \t\t experiment to consider, defaults to latest\n
-sf, --sarfile \t  will look for data at {sarfile}${SAREXT}\n
>>>>>>> Stashed changes
-sc, --sarcol \t\t  select a column in sar file\n
-t1, --start \t\t start unix time to filter\n
-t2, --end \t\t end unix time to filter\n
-fc, --filtercol \t column name to filter rows (e.g., where colname=colvalue)\n
-fv, --filterval \t column value to filter rows (e.g., where colname=colvalue)\n
-of, --outfile \t output to a file instead of stdout"

for i in "$@"
do
case $i in
<<<<<<< Updated upstream
    -sf=*|--sarfile=*)
    SARFILE="${i#*=}"
=======
    -n=*|--name=*)
    NAME="${i#*=}"
    ;;

    -sf=*|--sarfile=*)
    SARFILE_PFX="${i#*=}"
    SARFILE="${i#*=}${SAREXT}"
>>>>>>> Stashed changes
    ;;

    -sc=*|--sarcol=*)
    SARCOL="${i#*=}"
    ;;

<<<<<<< Updated upstream
    -t1=*|-st=*|--start=*)
    START="${i#*=}"
    ;;

    -t2=*|-et=*|--end=*)
=======
    -t1=*|--start=*)
    START="${i#*=}"
    ;;

    -t2=*|--end=*)
>>>>>>> Stashed changes
    END="${i#*=}"
    ;;

    -fc=*|--filtercol=*)
    FILTERCOL="${i#*=}"
    ;;
    
    -fv=*|--filterval=*)
    FILTERVAL="${i#*=}"
    ;;

    -of=*|--outfile=*)
    OUTFILE="${i#*=}"
    ;;

    *)                      # unknown option
    echo "Unkown Option: $i"
    echo -e $usage
    exit
    ;;
esac
done

# params
<<<<<<< Updated upstream
if [[ ! $SARFILE ]] || [[ ! $SARCOL ]]; then echo "must provide -sf and -sc"; echo -e $usage; exit 1; fi
if [ ! -f $SARFILE ];then   echo "no file found at path: ${SARFILE}";  exit 1;    fi

# get header/cols
header=$(cat $SARFILE | tail -n+3 | grep -w "$SARCOL" | head -n1)
=======
latest_dir_path=$(ls -td -- $DATADIR/*/ | head -n 1)
name=${NAME:-$(basename $latest_dir_path)}
if [ ! -d $expdir ];then   echo "no experment with name: ${name}";  exit 1;    fi
if [[ ! $SARFILE ]] || [[ ! $SARCOL ]]; then echo "must provide -sf and -sc"; echo -e $usage; exit 1; fi
# echo "Parsing sar for experiment:" $name
expdir=$DATADIR/$name

# get header/cols
header=$(cat $expdir/$SARFILE | tail -n+3 | grep -w "$SARCOL" | head -n1)
>>>>>>> Stashed changes
if [ -z "$header" ]; then   echo "can't find '$SARCOL'"; exit 1;    fi
cols=$(echo $header | awk '{for (i=0; i<=NF; i++) {
        switch(i) {
            case 0: break;
            case 1: print "unixtime";   break;       /* we run sar with ts  */
            case 2: print "systime1";   break;       /* sar prints sys time */
            case 3: print "systime2";   break;       /* sar prints sys time */
            default: print $i;
        }
     }}')
NCOLS=$(echo "$cols" | wc -l)

# filter rows
FCOL_IDX=1
FCOL_VAL=0
FCOL_CMP_OP="!="
if [[ $FILTERCOL ]]; then 
    FCOL_IDX=$(echo "$cols" | grep -w -n "$FILTERCOL" | cut -f1 -d:)
    if [ -z "$FCOL_IDX" ];  then echo "cannot find fc=$FILTERCOL. Available: "; echo $cols; exit 1; fi
    FCOL_VAL=${FILTERVAL:-'""'}
    FCOL_CMP_OP="=="
fi
FCOL_EXPR='$'${FCOL_IDX}${FCOL_CMP_OP}${FCOL_VAL}

# values
COLIDX=$(echo "$cols" | grep -w $SARCOL -n | cut -f1 -d:)
<<<<<<< Updated upstream
values=$(cat $SARFILE                       \
=======
values=$(cat $expdir/$SARFILE                       \
>>>>>>> Stashed changes
    | grep -v "$SARCOL"                             \
    | awk '{ if (NF == '$NCOLS') print $0 }'        \
    | awk '{ if ($1 >= '$START') print $0 }'        \
    | awk '{ if ($1 <= '$END')   print $0 }'        \
    | awk '{ if ('${FCOL_EXPR}') print $0 } '       \
    | awk '{ print $'$COLIDX' }')

if [[ $OUTFILE ]]; then 
    echo $SARCOL > ${OUTFILE}
    echo "$values" >> $OUTFILE
else 
    echo $SARCOL
    echo "$values"
fi
