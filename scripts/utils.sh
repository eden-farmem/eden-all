#!/bin/bash

#
# bash utils
#

max() {
    VALUES="$1"
    if [[ $VALUES ]]; then 
        echo "$VALUES" | awk '{ if (max=="") { max=$1 }; 
            if ($1 > max) { max=$1 }; } END { print max }'
    fi
}

min() {
    VALUES="$1"
    if [[ $VALUES ]]; then 
        echo "$VALUES" | awk '{ if (min=="") { min=$1 }; 
            if ($1 < min) { min=$1 }; } END { print min }'
    fi
}

mean() {
    VALUES="$1"
    if [[ $VALUES ]]; then 
        echo "$VALUES" | awk '{ s += $0; n++ } 
            END { if (n > 0) printf "%d", s/n }'
    fi
}

stdev(){
    VALUES="$1"
    if [[ $VALUES ]]; then 
        echo "$VALUES" | awk '{ x+=$0; y+=$0^2; n++ } 
            END { if (n > 0) print sqrt(y/n-(x/n)^2)}'
    fi
}

sum() {
    VALUES="$1"
    if [[ $VALUES ]]; then 
        echo "$VALUES" | awk '{ s += $0; n++ } 
            END { if (n > 0) printf "%d", s }'
    fi
}

count() {
    VALUES="$1"
    if [[ $VALUES ]]; then 
        echo "$VALUES" | awk '{ n++ } 
            END { if (n > 0) printf "%d", n }'
    fi
}

percentof(){
    NUMERATOR=$1
    DENOMINATOR=$2
    if [[ $NUMERATOR ]] && [[ $DENOMINATOR ]]; then
        echo $NUMERATOR $DENOMINATOR | awk '{ printf "%.1f", $1*100/$2 }'
    fi
}

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

csv_column_as_str() {
    FILE=$1
    COLNAME=$2
    values=$(csv_column "$FILE" "$COLNAME")
    if [[ $values ]]; then 
        # return as comma-separated string
        echo "$values" | paste -s -d, -
    fi
}

csv_column_mean() {
    FILE=$1
    COLNAME=$2
    values=$(csv_column "$FILE" "$COLNAME")
    mean "$values"
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

csv_column_sum() {
    FILE=$1
    COLNAME=$2
    values=$(csv_column "$FILE" "$COLNAME")
    sum "$values"
}

csv_column_max() {
    FILE=$1
    COLNAME=$2
    values=$(csv_column "$FILE" "$COLNAME")
    max "$values"
}

csv_column_min() {
    FILE=$1
    COLNAME=$2
    values=$(csv_column "$FILE" "$COLNAME")
    min "$values"
}

csv_column_count() {
    FILE=$1
    COLNAME=$2
    values=$(csv_column "$FILE" "$COLNAME")
    count "$values"
}

# tests
test_utils() {

    input="1
2
3
4
5"
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
}
test_utils