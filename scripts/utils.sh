#!/bin/bash

#
# Bash utils
#

# All local variables/functions are prefixed with UTILS_LOCAL_*
UTILS_LOCAL_usage="\n
-s, --show \t list all functions available\n
-t, --test \t run tests"

# Read parameters (only when the script is not being sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then 
    for i in "$@"
    do
    case $i in
        -s|--show)
        UTILS_LOCAL_show=1
        ;;

        -t|--test)
        UTILS_LOCAL_test=1
        ;;

        -*|--*)     # unknown option
        echo "Unknown Option: $i"
        echo -e $usage
        exit
        ;;
    esac
    done
fi

# Functions
max() {
    local VALUES="$1"
    if [[ $VALUES ]]; then 
        echo "$VALUES" | awk '{ if (max=="") { max=$1 }; 
            if ($1 > max) { max=$1 }; } END { print max }'
    fi
}

min() {
    local VALUES="$1"
    if [[ $VALUES ]]; then 
        echo "$VALUES" | awk '{ if (min=="") { min=$1 }; 
            if ($1 < min) { min=$1 }; } END { print min }'
    fi
}

mean() {
    local VALUES="$1"
    if [[ $VALUES ]]; then 
        echo "$VALUES" | awk '{ s += $0; n++ } 
            END { if (n > 0) printf "%d", s/n }'
    fi
}

stdev(){
    local VALUES="$1"
    if [[ $VALUES ]]; then 
        echo "$VALUES" | awk '{ x+=$0; y+=$0^2; n++ } 
            END { if (n > 0) print sqrt(y/n-(x/n)^2)}'
    fi
}

sum() {
    local VALUES="$1"
    if [[ $VALUES ]]; then 
        echo "$VALUES" | awk '{ s += $0; n++ } 
            END { if (n > 0) printf "%d", s }'
    fi
}

count() {
    local VALUES="$1"
    if [[ $VALUES ]]; then 
        echo "$VALUES" | awk '{ n++ } 
            END { if (n > 0) printf "%d", n }'
    fi
}

percentof() {
    local NUMERATOR=$1
    local DENOMINATOR=$2
    if [[ $NUMERATOR ]] && [[ $DENOMINATOR ]]; then
        echo $NUMERATOR $DENOMINATOR | awk '{ printf "%.1f", $1*100/$2 }'
    fi
}

ftoi() {
    ## float str to bash int ##
    local INPUT="$1"
    if [ -z "$1" ]; then read INPUT; fi
    echo "$INPUT" | awk '{  printf "%d", $1 }'
}

csv_column() {
    local FILE=$1
    local COLNAME=$2
    local header=$(head -n1 $FILE 2>/dev/null)
    local cols=$(echo $header | awk -F, '{for (i=1; i<=NF; i++) print $i}')
    local ncols=$(echo "$cols" | wc -l)
    local colidx=$(echo "$cols" | grep -w -n "$COLNAME" | cut -f1 -d:)
    if [ -z "$header" ] || [ -z "$ncols" ] || [ -z "$colidx" ]; then   
        # echo "couldn't find file or column" 1>&2
        return 
    fi

    values=$(tail -n+2 $FILE                            \
        | awk -F, '{ if (NF == '$ncols') print $0 }'    \
        | awk -F, '{ print $'$colidx' }')
    echo "$values"
}

csv_column_as_str() {
    local FILE=$1
    local COLNAME=$2
    local values=$(csv_column "$FILE" "$COLNAME")
    if [[ $values ]]; then 
        # return as comma-separated string
        echo "$values" | paste -s -d, -
    fi
}

csv_column_mean() {
    local FILE=$1
    local COLNAME=$2
    local values=$(csv_column "$FILE" "$COLNAME")
    mean "$values"
}

csv_column_stdev() {
    local FILE=$1
    local COLNAME=$2
    local values=$(csv_column "$FILE" "$COLNAME")
    # echo "$values"
    if [[ $values ]]; then 
        echo "$values" | awk '{ x+=$0; y+=$0^2; n++ } 
            END { if (n > 0) print sqrt(y/n-(x/n)^2)}'
    fi
}

csv_column_sum() {
    local FILE=$1
    local COLNAME=$2
    local values=$(csv_column "$FILE" "$COLNAME")
    sum "$values"
}

csv_column_max() {
    local FILE=$1
    local COLNAME=$2
    local values=$(csv_column "$FILE" "$COLNAME")
    max "$values"
}

csv_column_min() {
    local FILE=$1
    local COLNAME=$2
    local values=$(csv_column "$FILE" "$COLNAME")
    min "$values"
}

csv_column_count() {
    local FILE=$1
    local COLNAME=$2
    local values=$(csv_column "$FILE" "$COLNAME")
    count "$values"
}

# simple test cases
UTILS_LOCAL_run_tests() {
    numbers=("1" "2" "3" "4" "5")
    input=$(printf '%s\n' "${numbers[@]}")

    res=$(mean "$input")
    if [ "$res" != "3" ]; then echo "mean error"; fi

    res=$(stdev "$input")
    if [ "$res" != "1.41421" ]; then echo "stdev error"; fi  

    res=$(max "$input")
    if [ "$res" != "5" ]; then echo "max error"; fi

    res=$(min "$input")
    if [ "$res" != "1" ]; then echo "min error"; fi

    res=$(percentof 1 2)
    if [ "$res" != "50.0" ]; then echo "percentof error"; fi

    res=$(ftoi "50.012")        # input as cli
    if [ "$res" != "50" ]; then echo "ftoi error"; fi
    res=$(echo "60.012" | ftoi) # input through pipeing
    if [ "$res" != "60" ]; then echo "ftoi error"; fi

    echo "if you just see this text, all good!"
}

if [[ $UTILS_LOCAL_show ]]; then
    declare -F | grep -v "UTILS_LOCAL_" | cut -c 12-
fi

if [[ $UTILS_LOCAL_test ]]; then
    UTILS_LOCAL_run_tests
fi

# unset not-to-be-sourced locals
unset -v UTILS_LOCAL_USAGE
unset -v UTILS_LOCAL_show
unset -v UTILS_LOCAL_test
unset -f UTILS_LOCAL_run_tests