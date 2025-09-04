#!/usr/bin/env bash
# Run kill_by_name.sh remotely with argument "PASS" until only one remains

# --- Configuration ---
REMOTE_USER="dedongx"
REMOTE_IP="192.168.1.103"
SSH_KEY="/home/dedongx/.ssh/id_ed25519"
REMOTE_SCRIPT="/home/dedongx/power_aware_storage/kill_by_name.sh"
TARGET="PASS"

# --- Execution ---
ssh -i "$SSH_KEY" -o IdentitiesOnly=yes "${REMOTE_USER}@${REMOTE_IP}" \
    "sudo '$REMOTE_SCRIPT' '$TARGET'"
