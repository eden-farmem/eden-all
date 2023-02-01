#!/bin/bash

NFS_DATA_DIR='/home/ssgrant/eden-data/'
# data_dir='experiment_001-01-31-12-06-47'
# data_dir='experiment_001-02-01-12-21-41'
data_dir='crono_all_apps_feb_1_noaslr'
#da
heatmap_script='/usr/local/ssgrant/hotos_23/eden-all/scripts/prepare_heatmap.py'
output_directory='/usr/local/ssgrant/hotos_23/eden-all/hotos/exp_003/data'
percent=("95" "100")

pushd ${NFS_DATA_DIR}/${data_dir}
dirs=`ls --format=single-column  ./`

for d in ${dirs[@]}; do
    if [ ! -d $d ]; then
        continue
    fi

    # echo "Dir: $d"
    #collect the data files
    pushd $d
    dirs2=`ls --format=single-column  ./`

    traces=()
    for d2 in ${dirs2[@]}; do
        if [ ! -d $d2 ]; then
            continue
        fi
        if ! echo $d2 | grep -q "run"; then
            continue
        fi

        rel_filename="${d2}/trace/000_000.txt"
        full_filename=`realpath ${rel_filename}`

        if [ -f ${full_filename} ]; then
            traces+=(${full_filename})
        else
            echo "File: ${full_filename} does not exist skipping over"
        fi
    done
    # echo ${traces[@]}


    for p in ${percent[@]}; do
        echo "python ${heatmap_script} -i ${traces[@]} -p ${p} --reverse -o ${output_directory}/heatmap_${d}_${p}.txt"
        python ${heatmap_script} -i ${traces[@]} -p ${p} --reverse -o "${output_directory}/heatmap_${d}_${p}.txt"
    done
    # echo "python ${heatmap_script} -i ${traces[@]} -p ${percent} --reverse -o ${output_directory}/${d}_${percent}.txt"
    # python ${heatmap_script} -i ${traces[@]} -p ${percent} --reverse -o "${output_directory}/${d}_${percent}.txt"
    popd
done
popd