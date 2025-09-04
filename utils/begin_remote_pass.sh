#!/usr/bin/env bash
# Run PASS profile-based controller on remote via SSH

# --- Configuration ---
REMOTE_USER="dedongx"
REMOTE_IP="192.168.1.103"
SSH_KEY="/home/dedongx/.ssh/id_ed25519"
BASE_DIR="/home/dedongx/power_aware_storage"

# --- Default values ---
CONTROLLER="powercap_PASS_profile_based.py"

# --- Parse arguments ---
while getopts "c:" opt; do
  case "$opt" in
    c)
      case "$OPTARG" in
        SSD_BW_ONLY)
          CONTROLLER="powercap_PASS_profile_based_disk.py"
          ;;
        CPU_BW_ONLY)
          CONTROLLER="powercap_PASS_profile_based_cpu_bw.py"
          ;;
        CPU_JAILING_ONLY)
          CONTROLLER="powercap_PASS_profile_based_cpu_jailing.py"
          ;;
        RAPL_ONLY)
          CONTROLLER="powercap_PASS_profile_based_rapl.py"
          ;;
        *)
          echo "Unknown controller option: $OPTARG"
          echo "Valid options: SSD_BW_ONLY, CPU_BW_ONLY, CPU_JAILING_ONLY, RAPL_ONLY"
          exit 1
          ;;
      esac
      ;;
  esac
done

REMOTE_SCRIPT="$BASE_DIR/$CONTROLLER"

# --- Execution ---
ssh -i "$SSH_KEY" -o IdentitiesOnly=yes "${REMOTE_USER}@${REMOTE_IP}" \
    "sudo python3 '$REMOTE_SCRIPT' > /dev/null 2>&1" &
