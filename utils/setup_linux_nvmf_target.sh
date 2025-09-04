# Run setup of remote Linux NVMe-oF target
# Using remote script that sets up the SPDK NVMe-oF target
#!/usr/bin/bash

set -euo pipefail

usage() {
  cat <<EOF
Usage: $0 [-u <remote_user>] [-ip <remote_ip>] [-p <remote_script_path>]
  -u,  --remote-user         Remote user to SSH (default: dedongx)
  -ip, --remote-ip           Remote IP address (default: 192.168.1.103)
  -p,  --remote-script-path  Full path to remote script (default: /home/dedongx/power_aware_storage/setup_cleanup_storage_application.sh)
  -h,  --help                Show this help
EOF
  exit 1
}

# Defaults
REMOTE_USER="dedongx"
REMOTE_IP="192.168.1.103"
REMOTE_SCRIPT="/home/dedongx/power_aware_storage/setup_cleanup_storage_application.sh"

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    -u|--remote-user)
      REMOTE_USER="$2"; shift 2;;
    -ip|--remote-ip)
      REMOTE_IP="$2"; shift 2;;
    -p|--remote-script-path)
      REMOTE_SCRIPT="$2"; shift 2;;
    -h|--help)
      usage;;
    *)
      echo "Unknown parameter: $1"; usage;;
  esac
done

echo "Running remote setup on ${REMOTE_USER}@${REMOTE_IP}: sudo ${REMOTE_SCRIPT} setup_linux_nvmf"

# Use a specific SSH_KEY
SSH_KEY="/home/dedongx/.ssh/id_ed25519"
ssh -i "$SSH_KEY" "${REMOTE_USER}@${REMOTE_IP}" "sudo ${REMOTE_SCRIPT} cleanup_linux_nvmf"
ssh -i "$SSH_KEY" "${REMOTE_USER}@${REMOTE_IP}" "sudo ${REMOTE_SCRIPT} setup_linux_nvmf"
