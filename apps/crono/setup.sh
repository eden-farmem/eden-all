#!/bin/bash

# git clone https://github.com/masabahmad/CRONO.git
# mv CRONO crono


### Uncomment this if you want to bring the files back to this directory
#collect each of the scripts from the lower directories
# for app in `find . | grep trace.sh`; do
#     dirname=`echo $app | cut -d "/" -f 4`
#     echo $dirname
#     cp $app ./trace_scripts/${dirname}_trace.sh
# done
# cp crono/apps/trace-lib.sh ./trace_scripts/trace_lib.sh
# ls trace_scripts

#distribute

echo "Copying Trace scripts to their respective directories from the master location"
for file in `ls trace_scripts`; do
    if [ $file == "trace_lib.sh" ]; then
        rm crono/apps/trace-lib.sh
        trace_lib_full=`realpath trace_scripts/$file`
        ln -s $trace_lib_full crono/apps/trace-lib.sh
        continue
    fi
    dir=`echo $file | cut -d "_" -f 1`
    rm ./crono/apps/$dir/trace.sh
    trace_full=`realpath trace_scripts/$file`
    ln -s $trace_full ./crono/apps/$dir/trace.sh
done

    


