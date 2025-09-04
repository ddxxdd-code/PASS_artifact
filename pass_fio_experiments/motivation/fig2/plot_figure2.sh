#!/bin/bash
# This script generates Figure 2 for the motivation section of the PASS paper.
# Estimated running time: 30 minutes

# power_budgets=(270 300 330 380 440)
power_budgets=(440 380 330 300 270)
# power_budgets=(270 330 440)

# Get current path and compute path to system configs
current_path=$(pwd)
configs_path="$current_path/../../../utils"

# We then start experiments for three different system setups
# Cleanup (optional)
# $configs_path/umount_all_10_nvmf_disks.sh
$configs_path/disconnect_nvmf_target.sh spdk
$configs_path/stop_spdk_nvmf_target.sh
# $configs_path/cleanup_spdk_nvmf_target.sh

# Then we run fio with different system setups

# 1. PASS with 8 cores
$configs_path/setup_spdk_nvmf_target.sh
$configs_path/begin_spdk_nvmf_target.sh
# Connect to nvmf disks
$configs_path/connect_nvmf_target.sh spdk
# Run fio for different power budgets
$configs_path/reset_remote_cpu.sh
$configs_path/begin_remote_pass.sh
for power_budget in ${power_budgets[@]}
do
    echo "Running fio using PASS for power budget: $power_budget"
    $configs_path/set_power_budget.sh $power_budget
    sleep 1
    fio rwrite_32k_linux_nvmf_9_disk_4k_1_disk_bursty.fio > pass_${power_budget}.log
done
$configs_path/end_remote_pass.sh
sleep 1
$configs_path/reset_remote_cpu.sh
# 2. Thunderbolt
$configs_path/run_remote_batched_rpc.sh "framework_set_dynamic_scheduler"
# Run fio for different power budgets
$configs_path/begin_remote_thunderbolt.sh
for power_budget in ${power_budgets[@]}
do
    echo "Running fio using Thunderbolt for power budget: $power_budget"
    $configs_path/set_power_budget.sh $power_budget
    sleep 1
    sudo fio rwrite_32k_linux_nvmf_9_disk_4k_1_disk_bursty.fio > thunderbolt_${power_budget}.log
done
$configs_path/end_remote_thunderbolt.sh
# Stop spdk and cleanup
echo "Stopping SPDK and cleaning up"
$configs_path/disconnect_nvmf_target.sh spdk
$configs_path/stop_spdk_nvmf_target.sh
$configs_path/cleanup_spdk_nvmf_target.sh

# Finally, we plot the results
# We first read through all log files and extract latency and throughput results
python3 extract_figure2_results.py
# We then plot the results and generate Figure 2
python3 plot_bursty_background.py
python3 plot_bursty_foreground.py