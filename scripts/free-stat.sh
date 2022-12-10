

#!/bin/bash

#
# Collect cgroup stats for Fastswap
#

while true
do
    (free -w | awk '
	/^(Mem|Swap)/{
            for(i=2; i<= NF; i++){
                printf ",%d",$i
            }
        }
    ' | ts %s && echo "")
    sleep 1
done