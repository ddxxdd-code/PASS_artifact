# Run experiuments on remote end and collect power measured
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

# Then run experiments for different system setups
# 1. PASS with 8 cores
$configs_path/setup_spdk_nvmf_target.sh spdk
$configs_path/begin_spdk_nvmf_target.sh
# Connect to nvmf disks
$configs_path/connect_nvmf_target.sh spdk
$configs_path/reset_remote_cpu.sh
# use PASS
$configs_path/begin_remote_pass.sh
echo "Starting power measurement for PASS 600s"
bash read_remote_power.sh pass_timeseries 600 &
echo "Starting FIO workload for PASS 600s"
fio rread_64k_linux_nvmf_10_disk_600s.fio > pass_timeseries.log &
bash issue_dynamic_power_budget.sh &
$configs_path/end_remote_pass.sh
# use Thunderbolt
$configs_path/reset_remote_cpu.sh
$configs_path/begin_remote_thunderbolt.sh
echo "Starting power measurement for Thunderbolt 600s"
bash read_remote_power.sh thunderbolt_timeseries 600 &
echo "Starting FIO workload for Thunderbolt 600s"
fio rread_64k_linux_nvmf_10_disk_600s.fio > thunderbolt_timeseries.log &
bash issue_dynamic_power_budget.sh &
$configs_path/end_remote_thunderbolt.sh
# cleanup
echo "Cleaning up"
# $configs_path/umount_all_10_nvmf_disks.sh
$configs_path/disconnect_nvmf_target.sh spdk
$configs_path/stop_spdk_nvmf_target.sh

# Plot results
python3 plot_figure13.py