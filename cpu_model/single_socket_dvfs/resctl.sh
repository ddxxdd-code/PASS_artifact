#!/bin/bash

# Script to configure the 'poller_test' cgroup v2:
# 1. Sets CPU affinity (cpuset.cpus) to a specific number of logical cores
#    exclusively from SOCKET 0, prioritizing hyperthread siblings together.
# 2. Sets CPU bandwidth limit (cpu.max) based on the number of assigned logical cores
#    and a percentage bandwidth.
# 3. Sets DVFS frequency on those cores (userspace governor + scaling_setspeed).
#
# Usage: ./resctl.sh <num_logical_cores_on_socket0> <bandwidth_percentage> <frequency_khz>
# Example: ./resctl.sh 8 50 2000000  (2 GHz)
# Requires root privileges.

set -euo pipefail

CGROUP_NAME="poller_test"
CGROUP_PATH="/sys/fs/cgroup/${CGROUP_NAME}"
TARGET_SOCKET=0
CPU_PERIOD=100000         # 100 ms
CPU_INFO_CMD="lscpu -p=CPU,CORE,SOCKET"

log_info()  { echo "INFO: $1"; }
log_warn()  { echo "WARN: $1" >&2; }
log_error() { echo "ERROR: $1" >&2; exit 1; }

# --- root check ---
[[ $EUID -ne 0 ]] && log_error "Must be run as root."

# --- args ---
if [ "$#" -ne 3 ]; then
    log_error "Usage: $0 <cores> <bandwidth%> <frequency_khz>"
fi
REQUESTED_CORES=$1
BANDWIDTH=$2
FREQ_KHZ=$3

[[ "$REQUESTED_CORES" =~ ^[0-9]+$ ]] && (( REQUESTED_CORES>0 )) \
    || log_error "Cores must be a positive integer."
[[ "$BANDWIDTH" =~ ^[0-9]+$ ]] && (( BANDWIDTH>=0 && BANDWIDTH<=100 )) \
    || log_error "Bandwidth must be 0–100."
[[ "$FREQ_KHZ" =~ ^[0-9]+$ ]] \
    || log_error "Frequency must be integer kHz."

# --- cgroup exists? ---
[[ -d "$CGROUP_PATH" ]] \
    || log_error "Cgroup '$CGROUP_NAME' not found; create it first."

# --- select cores on socket 0 ---
declare -A siblings
declare -a coords
declare -A socket_count

while IFS=',' read -r cpu core socket _; do
    [[ "$cpu" =~ ^# ]] && continue
    coord="$socket:$core"
    # default to 0 if unset, then add 1
    socket_count[$socket]=$(( ${socket_count[$socket]:-0} + 1 ))
    if [[ -z "${siblings[$coord]+_}" ]]; then
        siblings[$coord]="$cpu"
        coords+=("$coord")
    else
        siblings[$coord]+=",$cpu"
    fi
done < <($CPU_INFO_CMD)

# ensure we have at least one core on TARGET_SOCKET
if (( ${socket_count[$TARGET_SOCKET]:-0} == 0 )); then
    log_error "No cores on socket $TARGET_SOCKET."
fi

# ensure request <= available
if (( REQUESTED_CORES > ${socket_count[$TARGET_SOCKET]:-0} )); then
    log_error "Requested $REQUESTED_CORES > available ${socket_count[$TARGET_SOCKET]:-0} cores."
fi

# sort coords
IFS=$'\n' coords=($(printf "%s\n" "${coords[@]}" | sort -t: -k1,1n -k2,2n)); unset IFS

selected=()
count=0

for coord in "${coords[@]}"; do
    sock=${coord%%:*}
    [[ "$sock" -ne "$TARGET_SOCKET" ]] && continue
    IFS=',' read -ra cpus <<< "${siblings[$coord]}"
    need=$(( REQUESTED_CORES - count ))
    (( need <= 0 )) && break
    if (( ${#cpus[@]} <= need )); then
        selected+=( "${cpus[@]}" )
        count=$(( count + ${#cpus[@]} ))
    else
        selected+=( "${cpus[@]:0:need}" )
        count=$REQUESTED_CORES
        break
    fi
done

(( count == REQUESTED_CORES )) \
    || log_error "Internal error: selected $count of $REQUESTED_CORES cores."

# join and sort final list
IFS=$'\n' final=($(printf "%s\n" "${selected[@]}" | sort -n)); unset IFS
CPULIST=$(IFS=,; echo "${final[*]}")

# --- apply cpuset ---
echo "$CPULIST" > "${CGROUP_PATH}/cpuset.cpus" \
    || log_error "Failed to write cpuset.cpus."

# --- apply cpu.max ---
if (( BANDWIDTH == 100 )); then
    CM="max $CPU_PERIOD"
else
    Q=$(( REQUESTED_CORES * BANDWIDTH * CPU_PERIOD / 100 ))
    (( Q<1 && BANDWIDTH>0 )) && Q=1
    CM="$Q $CPU_PERIOD"
fi
echo "$CM" > "${CGROUP_PATH}/cpu.max" \
    || log_error "Failed to write cpu.max."

# --- apply DVFS frequency ---
log_info "Setting userspace governor + ${FREQ_KHZ} kHz on: $CPULIST"
for cpu in "${final[@]}"; do
    dir="/sys/devices/system/cpu/cpu${cpu}/cpufreq"
    [[ -d "$dir" ]] || { log_warn "No cpufreq for cpu${cpu}"; continue; }
    echo userspace > "${dir}/scaling_governor" \
        || log_warn "gov on cpu${cpu} failed"
    echo "$FREQ_KHZ" > "${dir}/scaling_setspeed" \
        || log_warn "freq on cpu${cpu} failed"
done

# --- summary ---
echo "Configuration done:"
echo " cgroup:    $CGROUP_PATH"
echo " cpuset:    $(< ${CGROUP_PATH}/cpuset.cpus)"
echo " cpu.max:   $(< ${CGROUP_PATH}/cpu.max)"
echo " DVFS freq: ${FREQ_KHZ} kHz on ${#final[@]} cores"
exit 0

