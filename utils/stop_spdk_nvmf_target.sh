#!/usr/bin/env bash
# remote_kill_nvmf_tgt.sh
# SSH to a remote host using a specific ed25519 key and run:
#   sudo /home/dedongx/power_aware_storage/kill_by_name.sh nvmf_tgt

set -euo pipefail

usage() {
  cat <<EOF
Usage: $0 [-u <remote_user>] [-ip <remote_ip>] [-s <remote_script_path>] [-k <ssh_key_path>]
  -u,  --remote-user     Remote SSH user (default: dedongx)
  -ip, --remote-ip       Remote IP address (default: 192.168.1.103)
  -s,  --remote-script   Path to kill_by_name.sh on remote (default: /home/dedongx/power_aware_storage/kill_by_name.sh)
  -k,  --key             Path to ed25519 private key (default: /home/dedongx/.ssh/id_ed25519)
  -h,  --help            Show this help
EOF
  exit 1
}

# Defaults
REMOTE_USER="dedongx"
REMOTE_IP="192.168.1.103"
REMOTE_SCRIPT="/home/dedongx/power_aware_storage/kill_by_name.sh"
SSH_KEY="/home/dedongx/.ssh/id_ed25519"

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    -u|--remote-user)   REMOTE_USER="$2"; shift 2 ;;
    -ip|--remote-ip)    REMOTE_IP="$2"; shift 2 ;;
    -s|--remote-script) REMOTE_SCRIPT="$2"; shift 2 ;;
    -k|--key)           SSH_KEY="$2"; shift 2 ;;
    -h|--help)          usage ;;
    *) echo "Unknown parameter: $1"; usage ;;
  esac
done

# Sanity checks
if [[ ! -f "$SSH_KEY" ]]; then
  echo "Error: SSH key not found at: $SSH_KEY" >&2
  exit 1
fi

echo "Executing on ${REMOTE_USER}@${REMOTE_IP} using key ${SSH_KEY}: sudo ${REMOTE_SCRIPT} nvmf_tgt"

# You can tweak SSH options below if needed (e.g., StrictHostKeyChecking=no)
ssh -i "$SSH_KEY" -o IdentitiesOnly=yes "${REMOTE_USER}@${REMOTE_IP}" \
  "sudo ${REMOTE_SCRIPT} nvmf_tgt"

sleep 5