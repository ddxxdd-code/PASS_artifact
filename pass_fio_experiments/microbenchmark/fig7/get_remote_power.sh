#!/usr/bin/env bash
set -euo pipefail

# --- Configuration (edit if needed) ---
REMOTE_USER="dedongx"
REMOTE_IP="192.168.1.103"
SSH_KEY="/home/dedongx/.ssh/id_ed25519"

REMOTE_SCRIPT="/home/dedongx/fio_test/collect_rapl_ipmi_power_fans_speed.sh"
REMOTE_RESULTS_DIR="/home/dedongx/fio_test/results"

# --- Args ---
if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <basename>"
  echo "Example: $0 1725231234_system_cpu_power"
  exit 1
fi

BASENAME="$1"                     # e.g. 1725231234_system_cpu_power
LOCAL_OUT_DIR="${LOCAL_OUT_DIR:-./}"

# --- Derived ---
SSH_OPTS=(-i "$SSH_KEY" -o IdentitiesOnly=yes)
outfile_base="$REMOTE_RESULTS_DIR/$BASENAME"
remote_power="${outfile_base}.power"
remote_rapl="${outfile_base}.raplpower"

# --- Ensure local output dir exists ---
mkdir -p "$LOCAL_OUT_DIR"

echo "==> Running remote collector for 180s..."
ssh "${SSH_OPTS[@]}" "${REMOTE_USER}@${REMOTE_IP}" \
  "sudo -n '$REMOTE_SCRIPT' -t 180 -d '$REMOTE_RESULTS_DIR' -e '${BASENAME#*_}'"

echo "==> Copying back results..."
scp -i "$SSH_KEY" -o IdentitiesOnly=yes \
  "${REMOTE_USER}@${REMOTE_IP}:'$remote_power'" \
  "${REMOTE_USER}@${REMOTE_IP}:'$remote_rapl'" \
  "$LOCAL_OUT_DIR/"

echo "==> Done. Files saved in $LOCAL_OUT_DIR:"
ls -lh "$LOCAL_OUT_DIR/$(basename "$remote_power")" "$LOCAL_OUT_DIR/$(basename "$remote_rapl")"
