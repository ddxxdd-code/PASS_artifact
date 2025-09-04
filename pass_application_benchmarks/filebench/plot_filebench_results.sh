#!/usr/bin/env bash
# Orchestrate Filebench experiments using run_all_filebench_tests.sh
# Schedulers/caps:
#   - linux:        500 (unlimited)
#   - pass:         500 265 300 350 400
#   - thunderbolt:  500 265 300 350 400
#
# Log layout expected by aggregate_filebench_results_p99.py:
#   <scheduler>_<cap>/TIMESTAMP_<workload>_<disk>.log
#
# This script ensures we run run_all_filebench_tests.sh from inside the
# corresponding <scheduler>_<cap>/ directory so outputs land correctly.
set -euo pipefail

# ───────────────────────────── Paths ─────────────────────────────
current_path=$(pwd)
configs_path="$current_path/../../utils"

RUN_ALL="./run_all_filebench_tests.sh"
AGG_SH="./aggregate_filebench_results.sh"

# ─────────────────────────── Validations ─────────────────────────
[[ -x "$RUN_ALL" ]] || { echo "ERROR: $RUN_ALL not found or not executable."; exit 1; }
[[ -x "$AGG_SH"   ]] || { echo "ERROR: $AGG_SH not found or not executable.";   exit 1; }
command -v python3 >/dev/null || { echo "ERROR: python3 not in PATH."; exit 1; }

# ────────────────────────── Parameters ──────────────────────────
PASS_CAPS=(500 265 300 350 400)
TB_CAPS=(500 265 300 350 400)
LINUX_CAPS=(500)

CONNECT_SLEEP=1
BUDGET_SLEEP=1

# ─────────────────────────── Helpers ────────────────────────────
pause() { sleep "${1:-1}"; }
ensure_dir() { mkdir -p "$1"; }
pushd_quiet() { pushd "$1" >/dev/null; }
popd_quiet() { popd >/dev/null; }

rebuild_and_mount() {
  # Recreate FS & mount the 10 NVMeoF exports
  "$configs_path/rebuild_filesystem_nvmf_disks.sh"
  "$configs_path/mount_all_10_disks.sh"
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
  "$configs_path/clean_remote_target_all_10_disks.sh"
  set -e
}

run_all_into_dir() {
  # $1 = scheduler (linux|pass|thunderbolt), $2 = cap
  local sched cap outdir
  sched="$1"
  cap="$2"
  outdir="${sched}_${cap}"

  ensure_dir "$outdir"
  echo "[RUN] $sched (cap=$cap) via $RUN_ALL ..."
  "$RUN_ALL" -s "$outdir"
}

# ─────────────────────────── Flow ───────────────────────────────
echo "[CLEANUP] pre-run"
cleanup_all
echo 0 > /proc/sys/kernel/randomize_va_space

# ───────────────── 1) Linux NVMe-oF @ 500W only ─────────────────
echo "[LINUX] setup Linux NVMe-oF"
"$configs_path/setup_linux_nvmf_target.sh"
"$configs_path/connect_nvmf_target.sh" linux_nvmf
pause "$CONNECT_SLEEP"

echo "[LINUX] rebuild & mount"
rebuild_and_mount

for cap in "${LINUX_CAPS[@]}"; do
  # 500 means “unlimited” per your instructions
  echo "[LINUX] run_all (cap=$cap)"
  run_all_into_dir "linux" "$cap"
done

echo "[LINUX] unmount & disconnect"
umount_all
"$configs_path/disconnect_nvmf_target.sh" linux_nvmf
"$configs_path/cleanup_linux_nvmf_target.sh"
pause "$CONNECT_SLEEP"

# ──────── 2) SPDK bring-up (shared by PASS & Thunderbolt) ───────
echo "[SPDK] setup"
"$configs_path/clean_remote_target_all_10_disks.sh"
"$configs_path/setup_spdk_nvmf_target.sh"
"$configs_path/begin_spdk_nvmf_target.sh"
"$configs_path/connect_nvmf_target.sh" spdk
pause "$CONNECT_SLEEP"

# ───────────────────── 2a) PASS caps loop ───────────────────────
echo "[PASS] begin controller"
"$configs_path/reset_remote_cpu.sh" || true
"$configs_path/begin_remote_pass.sh"

for cap in "${PASS_CAPS[@]}"; do
  echo "[PASS] set power budget ${cap}W"
  "$configs_path/set_power_budget.sh" "$cap"
  pause "$BUDGET_SLEEP"

  echo "[PASS] rebuild & mount"
  rebuild_and_mount

  run_all_into_dir "pass" "$cap"

  echo "[PASS] unmount disks"
  umount_all
done

echo "[PASS] end controller & reset CPU"
"$configs_path/end_remote_pass.sh"
"$configs_path/set_remote_cpu_schedutil.sh" 

# ─────────────── 2b) Thunderbolt/Dynamic caps loop ──────────────
echo "[TB] configure dynamic scheduler"
"$configs_path/run_remote_batched_rpc.sh" "framework_set_dynamic_scheduler"

echo "[TB] begin service"
"$configs_path/begin_remote_thunderbolt.sh"

for cap in "${TB_CAPS[@]}"; do
  echo "[TB] set power budget ${cap}W"
  "$configs_path/set_power_budget.sh" "$cap"
  pause "$BUDGET_SLEEP"

  echo "[TB] rebuild & mount"
  rebuild_and_mount

  run_all_into_dir "thunderbolt" "$cap"

  echo "[TB] unmount disks"
  umount_all
done

echo "[TB] end service"
"$configs_path/end_remote_thunderbolt.sh"

# ──────────────────────── 3) Tear down SPDK ─────────────────────
echo "[SPDK] disconnect & stop"
"$configs_path/disconnect_nvmf_target.sh" spdk
stop_spdk_all

# ──────────────── 4) Aggregate & Plot everything ────────────────
aggregate_one() {
  local sched="$1" cap="$2"
  echo "[AGG] $sched $cap"
  "$AGG_SH" -s "$sched" -c "$cap"
}

echo "[AGG] run aggregations"
aggregate_one linux 500

for cap in "${PASS_CAPS[@]}"; do
  aggregate_one pass "$cap"
done

for cap in "${TB_CAPS[@]}"; do
  aggregate_one thunderbolt "$cap"
done

# If you require a literal misspelling folder "thderbolt_500" for compatibility,
# provide a symlink:
if [[ -d thunderbolt_500 && ! -e thderbolt_500 ]]; then
  ln -s thunderbolt_500 thderbolt_500
fi

echo "plot_filebench_workloads_max_power_one_figure.py"
python3 plot_filebench_workloads_max_power_one_figure.py

echo "All runs delegated to run_all_filebench_tests.sh, aggregated, and plotted."
