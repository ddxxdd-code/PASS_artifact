#!/bin/bash
# This script generates Figure 1 for the motivation section of the PASS paper.

# Get current path and compute path to system configs
current_path=$(pwd)
configs_path="$current_path/../../../utils"

# We first generate fio configurations for different background workload intensities
# generate for num_jobs from 0 to 8 and with fixed running period of 30s
for num_jobs in {0..8}
do
    python3 foreground_1_bursty_disk_background_9_disks_gen_fio_config.py -n $num_jobs -t 30
done

# We then start experiments for three different system setups
# Cleanup
$configs_path/umount_all_10_nvmf_disks.sh
$configs_path/disconnect_nvmf_target.sh spdk
$configs_path/disconnect_nvmf_target.sh linux_nvmf
$configs_path/stop_spdk_nvmf_target.sh
$configs_path/cleanup_spdk_nvmf_target.sh
$configs_path/set_remote_cpu_schedutil.sh

# Then we run fio with different system setups
# 1. Native Linux
$configs_path/setup_linux_nvmf_target.sh
# Connect to nvmf disks
$configs_path/connect_nvmf_target.sh linux_nvmf
echo "connected to linux nvmf target"
sleep 1
# Run fio for different background workload intensities and collect results
for num_jobs in {0..8}
do
    echo "Running fio for linux nvmf with $num_jobs background jobs"
    fio fig1_rwrite_32k_9_disk_bursty_4k_1_disk_n${num_jobs}_t30.fio > linux_n${num_jobs}_t30.log
    sleep 1
done
# Disconnect nvmf disks
$configs_path/disconnect_nvmf_target.sh linux_nvmf
$configs_path/cleanup_linux_nvmf_target.sh
sleep 1

# 2. SPDK with 8 cores
$configs_path/setup_spdk_nvmf_target.sh
$configs_path/begin_spdk_nvmf_target.sh
sleep 1
# Connect to nvmf disks
$configs_path/connect_nvmf_target.sh spdk
sleep 1
# Run fio for different background workload intensities and collect results
for num_jobs in {0..8}
do
    echo "Running fio for spdk static with $num_jobs background jobs"
    fio fig1_rwrite_32k_9_disk_bursty_4k_1_disk_n${num_jobs}_t30.fio > spdk_static_n${num_jobs}_t30.log
    sleep 1
done

# 3. SPDK dynamic
$configs_path/run_remote_batched_rpc.sh "framework_set_dynamic_scheduler"
# Run fio for different background workload intensities and collect results
for num_jobs in {0..8}
do
    echo "Running fio for spdk dynamic with $num_jobs background jobs"
    fio fig1_rwrite_32k_9_disk_bursty_4k_1_disk_n${num_jobs}_t30.fio > spdk_dynamic_n${num_jobs}_t30.log
    sleep 1
done
# Stop spdk and cleanup
$configs_path/disconnect_nvmf_target.sh spdk
$configs_path/stop_spdk_nvmf_target.sh
$configs_path/cleanup_spdk_nvmf_target.sh

# Finally, we plot the results
# We first read through all log files and extract latency and throughput results
python3 extract_fig1_results.py
# We then plot the results and generate Figure 1
python3 plot_figure1.py