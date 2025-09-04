#!/usr/bin/env bash
# Start SPDK nvmf_tgt remotely with sudo, then add its PID to a cgroup via /usr/bin/tee

set -euo pipefail

usage() {
  cat <<EOF
Usage: $0 [-u <remote_user>] [-ip <remote_ip>] [-b <nvmf_bin_path>] [-c <config_path>] [-n <num_cores>] [-k <ssh_key>] [-g <cgroup_procs_path>] [-h]
  -u,  --remote-user        Remote SSH user (default: dedongx)
  -ip, --remote-ip          Remote IP address (default: 192.168.1.103)
  -b,  --bin                Remote path to nvmf_tgt binary
                            (default: /home/dedongx/power_aware_storage/build/bin/nvmf_tgt)
  -c,  --config             Remote path to SPDK JSON config
                            (default: /home/dedongx/power_aware_storage/nvmf_rdma_10_disk_static_config.json)
  -n,  --cores              Number of cores to use (default: 8 → mask 0xFF). Example: 1 → 0x1
  -k,  --key                Path to ed25519 SSH private key (default: /home/dedongx/.ssh/id_ed25519)
  -g,  --cgroup-procs       Remote cgroup procs path to write PID into (default: /sys/fs/cgroup/user/procs)
  -h,  --help               Show this help

Notes:
- The remote command is run with 'sudo -n' (non-interactive). Configure passwordless sudo on the remote host.
- After starting, the PID is written to the cgroup procs file using /usr/bin/tee on the remote machine.
EOF
  exit 1
}

# Defaults
REMOTE_USER="dedongx"
REMOTE_IP="192.168.1.103"
REMOTE_BIN="/home/dedongx/power_aware_storage/build/bin/nvmf_tgt"
REMOTE_CONFIG="/home/dedongx/power_aware_storage/nvmf_rdma_10_disk_static_config.json"
NUM_CORES=8   # 8 -> 0xFF
SSH_KEY="/home/dedongx/.ssh/id_ed25519"
REMOTE_CGROUP_PROCS="/sys/fs/cgroup/user/cgroup.procs"

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    -u|--remote-user)   REMOTE_USER="$2"; shift 2;;
    -ip|--remote-ip)    REMOTE_IP="$2"; shift 2;;
    -b|--bin)           REMOTE_BIN="$2"; shift 2;;
    -c|--config)        REMOTE_CONFIG="$2"; shift 2;;
    -n|--cores)         NUM_CORES="$2"; shift 2;;
    -k|--key)           SSH_KEY="$2"; shift 2;;
    -g|--cgroup-procs)  REMOTE_CGROUP_PROCS="$2"; shift 2;;
    -h|--help)          usage;;
    *) echo "Unknown parameter: $1"; usage;;
  esac
done

# Validate
if ! [[ "$NUM_CORES" =~ ^[0-9]+$ ]] || (( NUM_CORES < 1 )); then
  echo "Error: --cores must be a positive integer (got: $NUM_CORES)"; exit 1
fi
if [[ ! -f "$SSH_KEY" ]]; then
  echo "Error: SSH key not found at: $SSH_KEY" >&2
  exit 1
fi

# Compute mask: (1<<NUM_CORES) - 1  -> hex (uppercase), prefixed 0x
MASK_DEC=$(( (1 << NUM_CORES) - 1 ))
CORE_MASK=$(printf '0x%X' "$MASK_DEC")

echo "Computed core mask for ${NUM_CORES} core(s): ${CORE_MASK}"
echo "Starting SPDK nvmf_tgt on ${REMOTE_USER}@${REMOTE_IP} (sudo) and adding PID to ${REMOTE_CGROUP_PROCS}..."

# Run remotely as root (sudo -n), background the target, capture its PID, then tee PID to cgroup
# We use a root shell ('sudo -n bash -lc') so /usr/bin/tee doesn't need sudo again.
PID="$(
  ssh -i "$SSH_KEY" -o IdentitiesOnly=yes "${REMOTE_USER}@${REMOTE_IP}" "
    nohup sudo ${REMOTE_BIN} -c ${REMOTE_CONFIG} -m ${CORE_MASK} >/dev/null 2>&1 &

    sleep 20

    pid=\$(pgrep -n -f \"nvmf_tgt\")
    printf %s\\\\n \"\$pid\" | sudo /usr/bin/tee ${REMOTE_CGROUP_PROCS} >/dev/null
    echo \$pid
  "
)"

# Basic sanity for PID
if ! [[ "$PID" =~ ^[0-9]+$ ]]; then
  echo "Failed to start remote process or capture PID (output was: $PID)" >&2
  echo "Tip: ensure passwordless sudo for both the nvmf_tgt command and writing to ${REMOTE_CGROUP_PROCS}." >&2
  exit 1
fi

echo "SPDK nvmf_tgt started on ${REMOTE_IP} with PID: ${PID}"
echo "PID ${PID} written to ${REMOTE_CGROUP_PROCS} on ${REMOTE_IP}"

# Optional pause as in your original script
# sleep 20
