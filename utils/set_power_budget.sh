#!/usr/bin/env bash
# write_remote_budget.sh
# Write numeric wattage to remote: /home/dedongx/power_aware_storage/budget

set -euo pipefail

usage() {
  cat <<EOF
Usage: $0 [-u <remote_user>] [-ip <remote_ip>] [-k <ssh_key>] [-f <remote_file>] [--sudo] <wattage>
  -u,  --remote-user   Remote SSH user (default: dedongx)
  -ip, --remote-ip     Remote IP address (default: 192.168.1.103)
  -k,  --key           Path to ed25519 SSH private key (default: /home/dedongx/.ssh/id_ed25519)
  -f,  --file          Remote file path (default: /home/dedongx/power_aware_storage/budget)
       --sudo          Use sudo on remote (writes via /usr/bin/tee; requires NOPASSWD or sudo prompt)
  -h,  --help          Show this help

Example:
  $0 350          # writes 350 to default remote file
  $0 --sudo 275.5 # writes 275.5 using sudo/tee on remote
EOF
  exit 1
}

# Defaults
REMOTE_USER="dedongx"
REMOTE_IP="192.168.1.103"
SSH_KEY="/home/dedongx/.ssh/id_ed25519"
REMOTE_FILE="/home/dedongx/power_aware_storage/budget"
USE_SUDO=0
WATTAGE=""

# Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    -u|--remote-user) REMOTE_USER="$2"; shift 2;;
    -ip|--remote-ip)  REMOTE_IP="$2"; shift 2;;
    -k|--key)         SSH_KEY="$2"; shift 2;;
    -f|--file)        REMOTE_FILE="$2"; shift 2;;
    --sudo)           USE_SUDO=1; shift 1;;
    -h|--help)        usage;;
    --)               shift; break;;
    -*)
      echo "Unknown option: $1" >&2; usage;;
    *)
      # First non-option is the wattage
      WATTAGE="$1"; shift 1;;
  esac
done

# Require wattage
if [[ -z "${WATTAGE}" ]]; then
  echo "Error: wattage value is required."; usage
fi

# Validate SSH key
if [[ ! -f "$SSH_KEY" ]]; then
  echo "Error: SSH key not found at: $SSH_KEY" >&2
  exit 1
fi

# Validate numeric (integer or float)
if ! [[ "$WATTAGE" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
  echo "Error: wattage must be numeric (e.g., 300 or 275.5), got: '$WATTAGE'" >&2
  exit 1
fi

REMOTE_DIR="$(dirname "$REMOTE_FILE")"

# Write to target
echo "Writing wattage '${WATTAGE}' to ${REMOTE_USER}@${REMOTE_IP}:${REMOTE_FILE} using key ${SSH_KEY}"
printf '%s' "$WATTAGE" | ssh -i "$SSH_KEY" -o IdentitiesOnly=yes "${REMOTE_USER}@${REMOTE_IP}" "${USE_SUDO:+sudo }/usr/bin/tee '$REMOTE_FILE' >/dev/null"

