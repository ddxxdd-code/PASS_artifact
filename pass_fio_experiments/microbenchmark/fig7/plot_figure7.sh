#!/bin/bash
# This script generates Figure 7 for the motivation section of the PASS paper.

power_budgets=(265 300 360 440 530)

# Get current path and compute path to system configs
current_path=$(pwd)
configs_path="$current_path/../../../utils"

# We then start experiments for three different system setups
# Cleanup
# $configs_path/umount_all_10_nvmf_disks.sh
# $configs_path/disconnect_nvmf_target.sh spdk
# $configs_path/disconnect_nvmf_target.sh linux_nvmf
# $configs_path/stop_spdk_nvmf_target.sh
# $configs_path/cleanup_spdk_nvmf_target.sh

# Then we run fio with different system setups

# 1. PASS with 8 cores
$configs_path/setup_spdk_nvmf_target.sh spdk
$configs_path/begin_spdk_nvmf_target.sh
# Connect to nvmf disks
$configs_path/connect_nvmf_target.sh spdk
# Run fio for different power budgets
# For different mechanisms
$configs_path/begin_remote_pass.sh
for power_budget in ${power_budgets[@]}
do
    $configs_path/set_power_budget.sh $power_budget
    sleep 1
    fio swrite_128k_linux_nvmf_10_disk.fio > pass_${power_budget}.log 2>&1 &
    get_remote_power.sh pass_${power_budget}
done
$configs_path/end_remote_pass.sh

# Stop spdk and cleanup
$configs_path/disconnect_nvmf_target.sh spdk
$configs_path/stop_spdk_nvmf_target.sh
$configs_path/cleanup_spdk_nvmf_target.sh

# Finally, we plot the results
# We first read through all log files and extract latency and throughput results
python3 extract_power_breakdown.py
# We then plot the results and generate Figure 7
python3 plot_figure7.py