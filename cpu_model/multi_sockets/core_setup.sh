### setting up cores ###


#!/bin/bash
set -e

usage() {
    cat <<EOF
Usage: $0 <num_cores|all|socketN>

  num_cores   Enable that many physical cores on socket 0, disable the rest on socket 0.
  all         Enable all CPUs, set governor to performance.
  socketN     Enable all CPUs on socket N, disable all others system-wide (e.g. socket0).

Examples:
  $0 4         # enable 4 physical cores on socket 0, disable the higher-ID cores on socket 0
  $0 all       # enable every CPU
  $0 socket1   # enable only CPUs on socket 1
EOF
    exit 1
}

if [ $# -ne 1 ]; then
    usage
fi

arg="$1"

# Helpers
bring_online() {
    local cpu=$1
    [ "$cpu" -eq 0 ] && return
    echo 1 > "/sys/devices/system/cpu/cpu${cpu}/online" 2>/dev/null || true
}
take_offline() {
    local cpu=$1
    [ "$cpu" -eq 0 ] && return
    echo 0 > "/sys/devices/system/cpu/cpu${cpu}/online" 2>/dev/null || true
}

# "all"
if [ "$arg" = "all" ]; then
    for cpu_dir in /sys/devices/system/cpu/cpu[0-9]*; do
        cpu=${cpu_dir##*cpu}
        echo "performance" > "$cpu_dir/cpufreq/scaling_governor" 2>/dev/null || true
        bring_online "$cpu"
    done
    exit 0
fi

# "socketN"
if [[ "$arg" =~ ^socket([0-9]+)$ ]]; then
    socket_id="${BASH_REMATCH[1]}"
    mapfile -t target_cpus < <(
        lscpu -p=CPU,SOCKET | grep -v '^#' | awk -F',' -v s="$socket_id" '$2==s {print $1}'
    )
    [ ${#target_cpus[@]} -eq 0 ] && { echo "No CPUs on socket $socket_id."; exit 2; }
    total=$(nproc)
    for cpu in $(seq 0 $((total-1))); do
        if [[ " ${target_cpus[*]} " =~ " $cpu " ]]; then
            echo "performance" > "/sys/devices/system/cpu/cpu${cpu}/cpufreq/scaling_governor" 2>/dev/null || true
            bring_online "$cpu"
        else
            take_offline "$cpu"
        fi
    done
    exit 0
fi

# numeric
if ! [[ "$arg" =~ ^[0-9]+$ ]]; then
    echo "Invalid argument: $arg"
    usage
fi

num_cores=$arg
# pick first N physical cores on socket 0
mapfile -t physical_cpus < <(
    lscpu -p=CPU,SOCKET,CORE \
    | grep -v '^#' \
    | awk -F',' '$2==0' \
    | sort -u -t',' -k3,3 \
    | head -n "$num_cores" \
    | cut -d',' -f1
)
[ "${#physical_cpus[@]}" -lt "$num_cores" ] && {
    echo "Found only ${#physical_cpus[@]} physical cores on socket 0, requested $num_cores."
    exit 2
}

# get all CPU IDs on socket 0
mapfile -t socket0_cpus < <(
    lscpu -p=CPU,SOCKET | grep -v '^#' | awk -F',' '$2==0 {print $1}'
)

# enable the selected and disable the larger IDs on socket 0
for cpu in "${socket0_cpus[@]}"; do
    if [[ " ${physical_cpus[*]} " =~ " $cpu " ]]; then
        echo "performance" > "/sys/devices/system/cpu/cpu${cpu}/cpufreq/scaling_governor" 2>/dev/null || true
        bring_online "$cpu"
    else
        take_offline "$cpu"
    fi
done

