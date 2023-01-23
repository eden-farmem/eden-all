#!/bin/bash

#clone and build
git clone https://github.com/masabahmad/CRONO.git
mv CRONO crono
pushd crono
make -j 30
popd

wget https://snap.stanford.edu/data/web-Google.txt.gz
gzip -d web-Google.txt.gz
rm web-Google.txt.gz
mv web-Google.txt crono/

pushd crono/apps/
mv triangle_counting triangle-counting
mv connected_components connected-components
popd


### Uncomment this if you want to bring the files back to this directory
#collect each of the scripts from the lower directories
# for app in `find . | grep trace.sh`; do
#     dirname=`echo $app | cut -d "/" -f 4`
#     echo $dirname
#     cp $app ./trace_scripts/${dirname}_trace.sh
# done
# cp crono/apps/trace-lib.sh ./trace_scripts/trace_lib.sh
# ls trace_scripts

#distribute trace libraries to the lower directories
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

    


