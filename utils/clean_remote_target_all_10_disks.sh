#!/usr/bin/env bash
# run_remote_erase.sh
#
# Usage:
#   ./run_remote_erase.sh
#
# This connects to your default server and runs:
#   sudo /home/dedongx/power_aware_storage/erase_all_disks.sh

set -euo pipefail

# --- Defaults ---
REMOTE_USER="dedongx"
REMOTE_IP="192.168.1.103"
SSH_KEY="/home/dedongx/.ssh/id_ed25519"
REMOTE_SCRIPT="/home/dedongx/power_aware_storage/erase_all_disks.sh"

# --- Run remote command ---
ssh -i "$SSH_KEY" \
    -o StrictHostKeyChecking=accept-new \
    -o IdentitiesOnly=yes \
    "${REMOTE_USER}@${REMOTE_IP}" \
    "sudo '$REMOTE_SCRIPT'"
