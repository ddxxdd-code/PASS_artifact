#!/usr/bin/env bash
# Orchestrate YCSB experiments using run_all_ycsb_tests.sh
# Systems & caps:
#   - linux:        500 (unlimited)
#   - pass:         500 265 300 350 400
#   - thunderbolt:  500 265 300 350 400
#
# Output layout:
#   <scheduler>_<cap>/... (logs/results produced by your YCSB runner)

set -euo pipefail

# ─────────────── Paths ───────────────
current_path=$(pwd)
configs_path="$current_path/../../../utils"

RUN_YCSB="./run_all_ycsb_tests.sh"  # your YCSB entrypoint
AGG_ONE="./compute_aggregated_all_workloads_bandwidths_method_and_cap.sh"
MERGE_ONE="./merge_aggregated_throughput_method_and_cap.py"
PLOT_ALL="./plot_ycsb_workloads_throughput_method_and_cap.py"

# ─────────────── Validations ─────────
[[ -x "$RUN_YCSB" ]] || { echo "ERROR: $RUN_YCSB not found or not executable."; exit 1; }
[[ -x "$AGG_ONE"  ]] || { echo "ERROR: $AGG_ONE not found or not executable.";  exit 1; }
command -v python3 >/dev/null || { echo "ERROR: python3 not in PATH."; exit 1; }

# ─────────────── Parameters ──────────
LINUX_CAPS=(500)
PASS_CAPS=(500 265 300 350 400)
TB_CAPS=(500 265 300 350 400)

# Map scheduler tag → YCSB aggregation "method" name
# Adjust these if your YCSB aggregation expects different identifiers.
declare -A METHOD_MAP=(
  [linux]="linux_rapl"
  [pass]="pass_profiled_new_new"
  [thunderbolt]="cpu_thunderbolt"
)

CONNECT_SLEEP=1
BUDGET_SLEEP=1

# ─────────────── Helpers ─────────────
pause() { sleep "${1:-1}"; }
ensure_dir() { mkdir -p "$1"; }
pushd_quiet() { pushd "$1" >/dev/null; }
popd_quiet() { popd >/dev/null; }

rebuild_and_mount() {
  "$configs_path/rebuild_filesystem_nvmf.sh"
  "$configs_path/mount_all_10_nvmf_disks.sh"
}

clean_mounted_disks() {
  # Clean AFTER mounting, BEFORE each YCSB run
  "$configs_path/clean_test_disks.sh"
}

umount_all() {
  "$configs_path/umount_all_10_nvmf_disks.sh" || true
}

disconnect_all() {
  "$configs_path/disconnect_nvmf_target.sh" spdk || true
  "$configs_path/disconnect_nvmf_target.sh" linux_nvmf || true
}

stop_spdk_all() {
  "$configs_path/stop_spdk_nvmf_target.sh" || true
  "$configs_path/cleanup_spdk_nvmf_target.sh" || true
}

cleanup_all() {
  set +e
  umount_all
  disconnect_all
  stop_spdk_all
  "$configs_path/cleanup_linux_nvmf_target.sh" || true
  set -e
}

run_ycsb_into_dir() {
  # $1 = scheduler (linux|pass|thunderbolt), $2 = cap
  local sched cap outdir
  sched="$1"
  cap="$2"
  outdir="${sched}_${cap}"

  ensure_dir "$outdir"
  echo "[RUN] YCSB: $sched (cap=$cap) via $RUN_YCSB"
  "$RUN_YCSB" -s "$outdir"
}

aggregate_method_cap() {
  # $1 = scheduler tag, $2 = cap
  local sched="$1" cap="$2"
  local method="${METHOD_MAP[$sched]}"
  if [[ -z "${method:-}" ]]; then
    echo "WARN: No method mapping for scheduler '$sched' — skipping aggregation."
    return 0
  fi
  echo "[AGG] method=${method}, powercap=${cap}"
  "$AGG_ONE" -m "${method}" -c "${cap}"
  python3 "$MERGE_ONE" -m "${method}" -c "${cap}"
}

# ─────────────── Flow ────────────────
echo "[CLEANUP] pre-run"
cleanup_all

# === 1) Linux NVMe-oF @ 500W ===
echo "[LINUX] setup Linux NVMe-oF"
"$configs_path/setup_linux_nvmf_target.sh"
"$configs_path/connect_nvmf_target.sh" linux_nvmf
pause "$CONNECT_SLEEP"

echo "[LINUX] rebuild & mount"
rebuild_and_mount
echo "[LINUX] clean mounted disks before YCSB"
clean_mounted_disks

for cap in "${LINUX_CAPS[@]}"; do
  echo "[LINUX] YCSB run_all (cap=$cap)"
  run_ycsb_into_dir "linux" "$cap"
  aggregate_method_cap "linux" "$cap"
done

echo "[LINUX] unmount & disconnect"
umount_all
"$configs_path/disconnect_nvmf_target.sh" linux_nvmf
"$configs_path/cleanup_linux_nvmf_target.sh"
pause "$CONNECT_SLEEP"

# === 2) SPDK bring-up (shared for PASS & Thunderbolt) ===
echo "[SPDK] setup"
"$configs_path/setup_spdk_nvmf_target.sh"
"$configs_path/begin_spdk_nvmf_target.sh"
"$configs_path/connect_nvmf_target.sh" spdk
pause "$CONNECT_SLEEP"

# --- 2a) PASS ---
echo "[PASS] begin controller"
"$configs_path/reset_remote_cpu.sh" || true
"$configs_path/begin_remote_pass.sh"

for cap in "${PASS_CAPS[@]}"; do
  echo "[PASS] set power budget ${cap}W"
  "$configs_path/set_power_budget.sh" "$cap"
  pause "$BUDGET_SLEEP"

  echo "[PASS] rebuild & mount"
  rebuild_and_mount
  echo "[PASS] clean mounted disks before YCSB"
  clean_mounted_disks

  run_ycsb_into_dir "pass" "$cap"
  aggregate_method_cap "pass" "$cap"

  echo "[PASS] unmount disks"
  umount_all
done

echo "[PASS] end controller & reset CPU"
"$configs_path/end_remote_pass.sh"
"$configs_path/reset_remote_cpu.sh" || true

# --- 2b) Thunderbolt/Dynamic ---
echo "[TB] configure dynamic scheduler"
"$configs_path/run_remote_batched_rpc.sh" "spdk_dynamic" || \
"$configs_path/run_remote_batched_rpc.sh" "framework_set_dynamic_scheduler" || true

echo "[TB] begin service"
"$configs_path/begin_remote_thunderbolt.sh"

for cap in "${TB_CAPS[@]}"; do
  echo "[TB] set power budget ${cap}W"
  "$configs_path/set_power_budget.sh" "$cap"
  pause "$BUDGET_SLEEP"

  echo "[TB] rebuild & mount"
  rebuild_and_mount
  echo "[TB] clean mounted disks before YCSB"
  clean_mounted_disks

  run_ycsb_into_dir "thunderbolt" "$cap"
  aggregate_method_cap "thunderbolt" "$cap"

  echo "[TB] unmount disks"
  umount_all
done

echo "[TB] end service"
"$configs_path/end_remote_thunderbolt.sh"

# === 3) Tear down SPDK ===
echo "[SPDK] disconnect & stop"
"$configs_path/disconnect_nvmf_target.sh" spdk
stop_spdk_all

# === 4) Final plotting ===
echo "[PLOT] $PLOT_ALL"
python3 "$PLOT_ALL"

echo "[DONE] YCSB pipeline complete."
