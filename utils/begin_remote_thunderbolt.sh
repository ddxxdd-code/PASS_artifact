#!/usr/bin/env bash
# Run thunderbolt controller on remote via SSH

# --- Configuration ---
REMOTE_USER="dedongx"
REMOTE_IP="192.168.1.103"
SSH_KEY="/home/dedongx/.ssh/id_ed25519"
REMOTE_SCRIPT="/home/dedongx/power_aware_storage/powercap_CPU_google.py"

# --- Execution ---
ssh -i "$SSH_KEY" -o IdentitiesOnly=yes "${REMOTE_USER}@${REMOTE_IP}" \
    "sudo python3 '$REMOTE_SCRIPT' > /dev/null 2>&1" &
