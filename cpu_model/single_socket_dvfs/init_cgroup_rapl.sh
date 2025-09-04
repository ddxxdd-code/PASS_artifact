#!/bin/bash

# Script to create a cgroup v2 named 'poller_test', ensure required
# controllers are enabled in the parent, initialize the cgroup,
# and set all socket-0 CPUs to max frequency via userspace DVFS.
# Requires root privileges.

CGROUP_NAME="poller_test"
CGROUP_PATH="/sys/fs/cgroup/${CGROUP_NAME}"
CGROUP_ROOT="/sys/fs/cgroup"

# --- Check for root ---
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi

# --- Check cgroup v2 ---
if ! mount | grep -q 'type cgroup2'; then
    echo "Error: cgroup v2 not mounted at ${CGROUP_ROOT}."
    exit 1
fi

# --- Enable controllers ---
REQUIRED_CONTROLLERS=("cpu" "cpuset")
PARENT_SUBTREE_CONTROL="${CGROUP_ROOT}/cgroup.subtree_control"
ENABLED_CONTROLLERS=$(<"${PARENT_SUBTREE_CONTROL}")

to_enable=()
for ctrl in "${REQUIRED_CONTROLLERS[@]}"; do
    if ! grep -qw "$ctrl" <<<"$ENABLED_CONTROLLERS"; then
        to_enable+=("+${ctrl}")
    fi
done

if ((${#to_enable[@]})); then
    echo "${to_enable[*]}" | tee -a "${PARENT_SUBTREE_CONTROL}" >/dev/null \
      || { echo "Error: cannot enable controllers."; exit 1; }
fi

# --- Create cgroup ---
if [[ ! -d "${CGROUP_PATH}" ]]; then
    mkdir "${CGROUP_PATH}" \
      || { echo "Error: cannot create ${CGROUP_PATH}."; exit 1; }
fi

# --- Initialize cgroup ---
echo "max 100000" > "${CGROUP_PATH}/cpu.max" \
  || { echo "Error: cannot set cpu.max."; exit 1; }

# --- Get socket-0 CPU list (e.g. "0-127,256-383") ---
cpulist=$(< /sys/devices/system/node/node0/cpulist)
if [[ -z "$cpulist" ]]; then
    echo "Error: empty socket-0 CPU list."; exit 1
fi

# Expand ranges into array of individual CPUs
cpus=()
IFS=',' read -r -a parts <<<"$cpulist"
for part in "${parts[@]}"; do
    if [[ $part == *-* ]]; then
        IFS='-' read -r start end <<<"$part"
        for ((i=start; i<=end; i++)); do
            cpus+=("$i")
        done
    else
        cpus+=("$part")
    fi
done

# Write cpuset
echo "$cpulist" > "${CGROUP_PATH}/cpuset.cpus" \
  || { echo "Error: cannot set cpuset.cpus."; exit 1; }

# --- DVFS: set all socket-0 CPUs to max freq via userspace ---
MAX_FREQ=$(< /sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq)
for cpu in "${cpus[@]}"; do
    dir="/sys/devices/system/cpu/cpu${cpu}/cpufreq"
    if [[ -d "$dir" ]]; then
        echo userspace > "${dir}/scaling_governor" \
          || { echo "Error: governor set failed on cpu${cpu}."; exit 1; }
        echo "${MAX_FREQ}" > "${dir}/scaling_setspeed" \
          || { echo "Error: setspeed failed on cpu${cpu}."; exit 1; }
    fi
done

# --- Enable threaded mode (if needed) ---
echo "threaded" > "${CGROUP_PATH}/cgroup.type"

echo "Initialization complete."
echo "  Path: ${CGROUP_PATH}"
echo "  cpu.max: $(< "${CGROUP_PATH}/cpu.max")"
echo "  cpuset.cpus: ${cpulist}"
echo "  DVFS max freq: ${MAX_FREQ} kHz on ${#cpus[@]} CPUs"
exit 0

