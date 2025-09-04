#!/usr/bin/bash
# run_remote_batched_rpc.sh
#
# Usage:
#   ./run_remote_batched_rpc.sh <input_name>
#
# Example:
#   ./run_remote_batched_rpc.sh framework_get_scheduler
#
# This executes on the remote:
#   /home/dedongx/power_aware_storage/scripts/rpc.py \
#     < /home/dedongx/power_aware_storage/batch_rpc_commands/<input_name>.txt

set -euo pipefail

# --- Defaults ---
REMOTE_USER="dedongx"
REMOTE_IP="192.168.1.103"
SSH_KEY="/home/dedongx/.ssh/id_ed25519"

REMOTE_RPC="/home/dedongx/power_aware_storage/scripts/rpc.py"
REMOTE_CMDDIR="/home/dedongx/power_aware_storage/batch_rpc_commands"

# --- Input check ---
if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <input_name>" >&2
  exit 1
fi
INPUT_NAME="$1"

# --- Build remote command ---
REMOTE_CMD="${REMOTE_RPC} < ${REMOTE_CMDDIR}/${INPUT_NAME}.txt"

# --- Run on remote ---
ssh -i "$SSH_KEY" -o StrictHostKeyChecking=accept-new \
    -o IdentitiesOnly=yes \
    "${REMOTE_USER}@${REMOTE_IP}" "sudo ${REMOTE_CMD}"
