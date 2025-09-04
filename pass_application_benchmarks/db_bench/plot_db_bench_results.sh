#!/usr/bin/env bash
# Orchestrate db_bench experiments using run_db_bench_tests_60s_int.sh
# Systems & caps:
#   - linux:        500 (unlimited)
#   - pass:         500 265 300 350 400
#   - thunderbolt:  500 265 300 350 400
#
# Layout expected:
#   <scheduler>_<cap>/... (logs/results produced by your db_bench runner)

set -euo pipefail

# ─────────────── Paths ───────────────
current_path=$(pwd)
configs_path="$current_path/../../utils"

# db_bench entry script(s)
RUN_DB_1="./run_db_bench_tests_60s_int.sh"   # preferred (from your screenshot)
RUN_DB_2="./db_bench_tests_60s_int"          # alternate name some trees use

# Aggregation & plotting
AGG_DB="./aggregate_all_db_bench_results.sh"
PLOT_DB="plot_db_bench_all_one_figure_insert_unlimited.py"

# ─────────────── Validations ─────────
if [[ -x "$RUN_DB_1" ]]; then RUN_DB="$RUN_DB_1"
elif [[ -x "$RUN_DB_2" ]]; then RUN_DB="$RUN_DB_2"
else
  echo "ERROR: Could not find executable db_bench runner: $RUN_DB_1 or $RUN_DB_2"
  exit 1
fi

[[ -x "$AGG_DB" ]] || { echo "ERROR: $AGG_DB not found or not executable."; exit 1; }
command -v python3 >/dev/null || { echo "ERROR: python3 not in PATH."; exit 1; }

# ─────────────── Parameters ──────────
LINUX_CAPS=(500)
PASS_CAPS=(500 265 300 350 400)
TB_CAPS=(500 265 300 350 400)

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
  # IMPORTANT: clean AFTER mounting, BEFORE running db_bench
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

run_db_into_dir() {
  # $1 = scheduler (linux|pass|thunderbolt), $2 = cap
  local sched cap outdir
  sched="$1"
  cap="$2"
  outdir="${sched}_${cap}"
  
  ensure_dir "$outdir"
  echo "[RUN] db_bench: $sched (cap=$cap) via $RUN_DB"
  # If your db_bench runner accepts -s like filebench, pass it along:
  "$RUN_DB" -s "$outdir"
}

aggregate_one() {
  local sched="$1" cap="$2"
  echo "[AGG] $sched $cap"
  # Assuming the aggregator mirrors filebench's interface:
  "$AGG_DB" -s "$sched" -c "$cap"
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
echo "[LINUX] clean mounted disks before db_bench"
clean_mounted_disks

for cap in "${LINUX_CAPS[@]}"; do
  echo "[LINUX] db_bench run_all (cap=$cap)"
  run_db_into_dir "linux" "$cap"
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
  echo "[PASS] clean mounted disks before db_bench"
  clean_mounted_disks

  run_db_into_dir "pass" "$cap"

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
  echo "[TB] clean mounted disks before db_bench"
  clean_mounted_disks

  run_db_into_dir "thunderbolt" "$cap"

  echo "[TB] unmount disks"
  umount_all
done

echo "[TB] end service"
"$configs_path/end_remote_thunderbolt.sh"

# === 3) Tear down SPDK ===
echo "[SPDK] disconnect & stop"
"$configs_path/disconnect_nvmf_target.sh" spdk
stop_spdk_all

# === 4) Aggregate & Plot ===
echo "[AGG] aggregate db_bench results for all systems/caps"
aggregate_one linux 500

for cap in "${PASS_CAPS[@]}"; do
  aggregate_one pass "$cap"
done

for cap in "${TB_CAPS[@]}"; do
  aggregate_one thunderbolt "$cap"
done

# Optional compatibility symlink (if anything expects thderbolt_500):
if [[ -d thunderbolt_500 && ! -e thderbolt_500 ]]; then
  ln -s thunderbolt_500 thderbolt_500
fi

echo "[PLOT] $PLOT_DB"
python3 "$PLOT_DB"

echo "[DONE] db_bench pipeline complete."
