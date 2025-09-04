# We need to setup SPDK running on remote and run PASS and Thunderbolt on it
#!/bin/bash

power_budgets=(440 360 300 265)

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
# For PASS
$configs_path/begin_remote_pass.sh
$configs_path/run_remote_batched_rpc.sh "qos_10m_last_9_disks"
for power_budget in ${power_budgets[@]}
do
    $configs_path/set_power_budget.sh $power_budget
    sleep 1
    fio rwrite_128k_linux_nvmf_9_disk.fio &
    fio rread_4k_linux_nvmf_1_disk.fio > pass_${power_budget}.log
    sleep 120
done
$configs_path/end_remote_pass.sh
# For thunderbolt
$configs_path/begin_remote_thunderbolt.sh
$configs_path/run_remote_batched_rpc.sh "qos_unlimited_all_10_disks"
for power_budget in ${power_budgets[@]}
do
    $configs_path/set_power_budget.sh $power_budget
    sleep 1
    fio rwrite_128k_linux_nvmf_9_disk.fio &
    fio rread_4k_linux_nvmf_1_disk.fio > thunderbolt_${power_budget}.log
    sleep 120
done
$configs_path/end_remote_thunderbolt.sh
# Stop spdk and cleanup
$configs_path/disconnect_nvmf_target.sh spdk
$configs_path/stop_spdk_nvmf_target.sh
$configs_path/cleanup_spdk_nvmf_target.sh

# Finally, we plot the results
# We first read through all log files and extract latency and throughput results
python3 extract_figure12_results.py #TODO
# We then plot the results and generate Figure 12
python3 plot_figure12.py #TODO