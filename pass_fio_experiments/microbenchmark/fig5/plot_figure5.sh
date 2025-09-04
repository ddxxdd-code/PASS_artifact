#!/bin/bash
# This script generates Figure 5 for the motivation section of the PASS paper.

# power_budgets=(250 260 300 360 440 600)
power_budgets=(600 440 360 300 260 250)

# Get current path and compute path to system configs
current_path=$(pwd)
configs_path="$current_path/../../../utils"

# We then start experiments for three different system setups
# Cleanup
# bash $configs_path/umount_all_10_nvmf_disks.sh
# bash $configs_path/disconnect_nvmf_target.sh spdk
# bash $configs_path/stop_spdk_nvmf_target.sh linux_nvmf
# bash $configs_path/cleanup_spdk_nvmf_target.sh

# Then we run fio with different system setups

# 1. PASS with 8 cores
$configs_path/setup_spdk_nvmf_target.sh spdk
$configs_path/begin_spdk_nvmf_target.sh
# Connect to nvmf disks
$configs_path/connect_nvmf_target.sh spdk
# Run fio for different power budgets
$configs_path/begin_remote_pass.sh
for power_budget in ${power_budgets[@]}
do
    $configs_path/set_power_budget.sh $power_budget
    sleep 1
    sudo fio swrite_128k_linux_nvmf_10_disk.fio > pass_c8d10_${power_budget}.log
done
$configs_path/end_remote_pass.sh
# Run fio for different power budgets
$configs_path/begin_remote_pass.sh
for power_budget in ${power_budgets[@]}
do
    $configs_path/set_power_budget.sh $power_budget
    sleep 1
    sudo fio swrite_128k_linux_nvmf_5_disk.fio > pass_c8d5_${power_budget}.log
done
$configs_path/end_remote_pass.sh
# 2. Thunderbolt
$configs_path/run_remote_batched_rpc.sh "framework_set_dynamic_scheduler"
# Run fio for different power budgets
$configs_path/begin_remote_thunderbolt.sh
for power_budget in ${power_budgets[@]}
do
    $configs_path/set_power_budget.sh $power_budget
    sleep 1
    sudo fio swrite_128k_linux_nvmf_10_disk.fio > thunderbolt_c8d10_${power_budget}.log
done
$configs_path/end_remote_thunderbolt.sh
# Run fio for different power budgets
$configs_path/begin_remote_thunderbolt.sh
for power_budget in ${power_budgets[@]}
do
    $configs_path/set_power_budget.sh $power_budget
    sleep 1
    sudo fio swrite_128k_linux_nvmf_5_disk.fio > thunderbolt_c8d5_${power_budget}.log
done
$configs_path/end_remote_thunderbolt.sh
# 3. single core PASS and thunderbolt
$configs_path/reset_remote_cpu.sh
$configs_path/disconnect_nvmf_target.sh spdk
$configs_path/stop_spdk_nvmf_target.sh
$configs_path/begin_spdk_nvmf_target.sh -n 1
# Connect to nvmf disks
$configs_path/connect_nvmf_target.sh spdk

# Run fio for different power budgets for PASS
$configs_path/begin_remote_pass.sh
for power_budget in ${power_budgets[@]}
do
    $configs_path/set_power_budget.sh $power_budget
    sleep 1
    sudo fio swrite_128k_linux_nvmf_10_disk.fio > pass_c1d10_${power_budget}.log
done
$configs_path/end_remote_pass.sh

# Run fio for different power budgets for Thunderbolt
$configs_path/run_remote_batched_rpc.sh "framework_set_dynamic_scheduler"
$configs_path/begin_remote_thunderbolt.sh
for power_budget in ${power_budgets[@]}
do
    $configs_path/set_power_budget.sh $power_budget
    sleep 1
    sudo fio swrite_128k_linux_nvmf_10_disk.fio > thunderbolt_c1d10_${power_budget}.log
done
$configs_path/end_remote_thunderbolt.sh

# Stop spdk and cleanup
$configs_path/disconnect_nvmf_target.sh spdk
$configs_path/stop_spdk_nvmf_target.sh
$configs_path/cleanup_spdk_nvmf_target.sh

# Finally, we plot the results
# We first read through all log files and extract latency and throughput results
python3 extract_figure5_results.py
# We then plot the results and generate Figure 5
python3 plot_figure5.py