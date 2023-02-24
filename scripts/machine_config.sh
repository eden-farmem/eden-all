#!/bin/bash

echo "setting up machine config after reboot"

# Disable turbo: This is temporary and only works with intel pstate driver
# https://askubuntu.com/questions/619875/disabling-intel-turbo-boost-in-ubuntu
echo "1" | sudo tee /sys/devices/system/cpu/intel_pstate/no_turbo

# Disable automatic NUMA load balancing. This feature raises spurious page 
# faults to determine NUMA node access patterns which interfere with 
# the VDSO-based annotations
echo 0 | sudo tee /proc/sys/kernel/numa_balancing

# Disable sudo requirement for userfaultfd
sudo sysctl -w vm.unprivileged_userfaultfd=1

# Disable ASLR
echo 0 | sudo tee /proc/sys/kernel/randomize_va_space

# disable freq scaling and set CPU to a static frequency
# Note that tools with daemons such as cpufrequtils may affect this
governor=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)
freq=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_min_freq)
if [ "$governor" != "performance" ] || [ "$freq" != "2200000" ]; then
    echo "setting cpu freq on all cores"
    N=`nproc`
    for ((cpu=0; cpu<$N; cpu++)); do
        cpudir=/sys/devices/system/cpu/cpu$cpu/cpufreq/
        if [ -d $dir ]; then
            echo "performance" | sudo tee ${cpudir}/scaling_governor
            echo 2200000 | sudo tee ${cpudir}/scaling_min_freq
            echo 2200000 | sudo tee ${cpudir}/scaling_max_freq
        fi
    done
fi
# # Check with 
# # cat /proc/cpuinfo | grep MHz