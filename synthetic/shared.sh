#!/bin/bash

#
# bash utils
#

csv_column() {
    FILE=$1
    COLNAME=$2

    header=$(head -n1 $FILE 2>/dev/null)
    cols=$(echo $header | awk -F, '{for (i=1; i<=NF; i++) print $i}')
    ncols=$(echo "$cols" | wc -l)
    colidx=$(echo "$cols" | grep -w -n "$COLNAME" | cut -f1 -d:)
    if [ -z "$header" ] || [ -z "$ncols" ] || [ -z "$colidx" ]; then   
        # echo "couldn't find file or column" 1>&2
        return 
    fi

    values=$(tail -n+2 $FILE                            \
        | awk -F, '{ if (NF == '$ncols') print $0 }'    \
        | awk -F, '{ print $'$colidx' }')
    echo "$values"
}

csv_column_mean() {
    FILE=$1
    COLNAME=$2
    values=$(csv_column "$FILE" "$COLNAME")
    # echo "$values"
    if [[ $values ]]; then 
        echo "$values" | awk '{ s += $0; n++ } 
            END { if (n > 0) printf "%d", s/n }'
    fi
}

csv_column_stdev() {
    FILE=$1
    COLNAME=$2
    values=$(csv_column "$FILE" "$COLNAME")
    # echo "$values"
    if [[ $values ]]; then 
        echo "$values" | awk '{ x+=$0; y+=$0^2; n++ } 
            END { if (n > 0) print sqrt(y/n-(x/n)^2)}'
    fi
}

# test
# csv_column_mean "data/run-05-16-05-51-10/kona_counters_parsed" "n_faults_r"
# csv_column_mean "data/run-05-08-19-50/kona_counters.out" "n_faults_w"
# csv_column_stdev "data/run-05-08-19-50/kona_counters.out" "n_faults_w"