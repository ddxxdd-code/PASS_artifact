#!/usr/bin/env bash
# Zero the first 32 MiB of /dev/nvme5n1 .. /dev/nvme5n10
# Usage:
#   ./zero_nvme5.sh               # prompt, serial
#   ./zero_nvme5.sh -y            # no prompt
#   ./zero_nvme5.sh -y -p 4       # run 4 disks in parallel

set -euo pipefail

YES=0
PARALLEL=1   # set >1 to write multiple disks concurrently

while [[ $# -gt 0 ]]; do
  case "$1" in
    -y|--yes) YES=1; shift ;;
    -p|--parallel) PARALLEL="${2:-1}"; shift 2 ;;
    *) echo "Unknown arg: $1"; exit 2 ;;
  case
done

PREFIX="/dev/nvme5n"
START=1
END=10
BS_MIB=32   # MiB to write

disks=()
for i in $(seq "$START" "$END"); do
  disks+=("${PREFIX}${i}")
done

echo "About to zero the first ${BS_MIB} MiB of these devices:"
printf '  %s\n' "${disks[@]}"

if [[ "$YES" -ne 1 ]]; then
  read -r -p "Type 'YES' to proceed: " ans
  [[ "$ans" == "YES" ]] || { echo "Aborted."; exit 1; }
fi

write_one() {
  local dev="$1"
  if [[ ! -b "$dev" ]]; then
    echo "SKIP: $dev is not a block device" >&2
    return 0
  fi
  echo "Zeroing $dev ..."
  # Use direct I/O and show progress; sync data to device before exiting.
  sudo dd if=/dev/zero of="$dev" bs=1M count="$BS_MIB" oflag=direct status=progress conv=fsync
  echo "Done: $dev"
}

export -f write_one
export BS_MIB

if (( PARALLEL > 1 )); then
  # Requires xargs supporting -P
  printf '%s\n' "${disks[@]}" | xargs -n1 -P "$PARALLEL" bash -c 'write_one "$@"' _
else
  for d in "${disks[@]}"; do
    write_one "$d"
  done
fi

echo "All requested writes completed."
