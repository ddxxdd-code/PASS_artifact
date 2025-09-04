#!/usr/bin/bash
set -Eeuo pipefail

# Must run as root
if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run with sudo or as root"
  exit 1
fi

# --- config ---
LOCKFILE="/var/lock/experiment_global.lock"   # or /tmp/my_global.lock
LOCKFD=315                              # any free FD
WAIT_SECS=5                             # wait up to 5s for the lock (set 0 for non-blocking)

# --- acquire the lock ---
acquire_lock() {
  # open a file descriptor tied to the lockfile
  exec {LOCKFD}>"$LOCKFILE"
  # try to lock; wait up to WAIT_SECS seconds (use -n for immediate failure)
  if ! flock -w "$WAIT_SECS" "$LOCKFD"; then
    echo "ERROR: lock already acquired by others. Timed out waiting for lock: $LOCKFILE" >&2
    exit 1
  fi
}

# --- cleanup: unlock (and optionally remove the lockfile name) ---
cleanup() {
  # releasing the FD is enough; the kernel drops the lock on exit anyway
  flock -u "$LOCKFD" || true
}
trap cleanup EXIT INT TERM HUP

# --- main ---
# ensure flock is present
command -v flock >/dev/null 2>&1 || { echo "ERROR: 'flock' not found."; exit 127; }

acquire_lock
echo "[$(date +%T)] acquired lock: $LOCKFILE (pid $$)"

echo "Start running experiments, estimated machine time ~12 hours."

# Run motivation figures 1, 2
echo "Running motivation figures 1, 2... [estimated time ~30 minutes]"

cd ./pass_fio_experiments/motivation/fig1
bash plot_figure1.sh

cd ../fig2
bash plot_figure2.sh

# Run microbenchmarks figure 4, 5, 6, 7, 11, 12, 13
echo "Running microbenchmarks figures 4, 5, 6, 7, 11, 12, 13... [estimated time ~1 hour]"

cd ../../pass_fio_experiments/microbenchmark/fig4
bash plot_figure4.sh

cd ../fig5
bash plot_figure5.sh

cd ../fig6
bash plot_figure6.sh

cd ../fig7
bash plot_figure7.sh

cd ../fig11
bash plot_figure11.sh

cd ../fig12
bash plot_figure12.sh

cd ../fig13
bash plot_figure13.sh

# Run application 
echo "Running application figures 8, 9, 10... [estimated time ~10 hours]"

cd ../../../pass_application_benchmarks
cd filebench
bash plot_filebench_results.sh

cd ../db_bench
bash plot_db_bench_results.sh

cd ../YCSB
bash plot_ycsb_results.sh

cd ../..

# End
echo "All experiments completed. Please check the results in the corresponding directories."