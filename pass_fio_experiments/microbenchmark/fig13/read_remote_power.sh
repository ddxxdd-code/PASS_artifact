#!/usr/bin/env bash
set -euo pipefail

# --- Configuration ---
REMOTE_USER="dedongx"
REMOTE_IP="192.168.1.103"
SSH_KEY="/home/dedongx/.ssh/id_ed25519"

REMOTE_SCRIPT="/home/dedongx/fio_test/collect_system_power.sh"
REMOTE_DIR="/home/dedongx/fio_test/results"   # matches your script's default

ssh_opts=(-i "$SSH_KEY" -o IdentitiesOnly=yes)

usage() {
  echo "Usage: $0 <base_name> [duration_seconds]"
  echo "Example: $0 pass_timeseries 600"
}

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

BASE_NAME="$1"                  # e.g., pass_timeseries
DURATION="${2:-600}"            # default 600s
LOCAL_OUT="${BASE_NAME}.log"    # local destination filename

echo "== Running remote collection =="
echo "Remote: $REMOTE_USER@$REMOTE_IP"
echo "Base name: $BASE_NAME"
echo "Duration: ${DURATION}s"

# Run the collector on the remote for DURATION seconds with experiment name = BASE_NAME.
# Then, print out the newest .power file path so we can scp it back.
REMOTE_OUT=$(
  ssh "${ssh_opts[@]}" "${REMOTE_USER}@${REMOTE_IP}" bash -lc "'
    set -euo pipefail
    mkdir -p \"$REMOTE_DIR\"
    sudo \"$REMOTE_SCRIPT\" -t ${DURATION} -d \"$REMOTE_DIR\" -e \"${BASE_NAME}\"

    POWER_OUT=\$(ls -1t \"$REMOTE_DIR\"/*_${BASE_NAME}.power | head -n1 || true)
    if [[ -z \"\${POWER_OUT}\" ]]; then
      echo \"ERROR: No power file produced for experiment ${BASE_NAME}\" >&2
      exit 2
    fi
    echo \"POWER:\${POWER_OUT}\"
  '"
)

# Parse POWER:path
POWER_PATH="$(echo "$REMOTE_OUT" | awk -F: '/^POWER:/{print $2}')"
if [[ -z "${POWER_PATH:-}" ]]; then
  echo "ERROR: Could not find remote power file."
  echo "Remote said:"
  echo "$REMOTE_OUT"
  exit 3
fi

echo "== Remote power file =="
echo "$POWER_PATH"

# Copy back and rename locally
scp "${ssh_opts[@]}" "${REMOTE_USER}@${REMOTE_IP}:${POWER_PATH}" "${LOCAL_OUT}"
echo "Saved: ${LOCAL_OUT}"
echo "== Done =="
