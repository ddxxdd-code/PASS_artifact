#!/bin/bash
# This script generates Figure 6 for the motivation section of the PASS paper.

power_budgets=(280 290 350 440 480)

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
    sleep 10
    fio rwrite_4k_linux_nvmf_10_disk.fio > pass_${power_budget}.log
done
$configs_path/end_remote_pass.sh
# SSD b/w only
$configs_path/begin_remote_pass.sh -c "SSD_BW_ONLY"
for power_budget in ${power_budgets[@]}
do
    $configs_path/set_power_budget.sh $power_budget
    sleep 10
    fio rwrite_4k_linux_nvmf_10_disk.fio > ssd_bw_only_${power_budget}.log
done
$configs_path/end_remote_pass.sh
# CPU b/w only
$configs_path/begin_remote_pass.sh -c "CPU_BW_ONLY"
for power_budget in ${power_budgets[@]}
do
    $configs_path/set_power_budget.sh $power_budget
    sleep 10
    fio rwrite_4k_linux_nvmf_10_disk.fio > cpu_bw_only_${power_budget}.log
done
$configs_path/end_remote_pass.sh
# CPU jailing only
$configs_path/begin_remote_pass.sh -c "CPU_JAILING_ONLY"
for power_budget in ${power_budgets[@]}
do
    $configs_path/set_power_budget.sh $power_budget
    sleep 10            
    fio rwrite_4k_linux_nvmf_10_disk.fio > cpu_jailing_only_${power_budget}.log
done
$configs_path/end_remote_pass.sh
# RAPL only
$configs_path/begin_remote_pass.sh -c "RAPL_ONLY"
for power_budget in ${power_budgets[@]}
do
    $configs_path/set_power_budget.sh $power_budget
    sleep 10
    fio rwrite_4k_linux_nvmf_10_disk.fio > rapl_only_${power_budget}.log
done
$configs_path/end_remote_pass.sh

# Stop spdk and cleanup
$configs_path/disconnect_nvmf_target.sh spdk
$configs_path/stop_spdk_nvmf_target.sh
$configs_path/cleanup_spdk_nvmf_target.sh

# Finally, we plot the results
# We first read through all log files and extract latency and throughput results
python3 extract_figure6_results.py #TODO
# We then plot the results and generate Figure 6
python3 plot_figure6.py #TODO