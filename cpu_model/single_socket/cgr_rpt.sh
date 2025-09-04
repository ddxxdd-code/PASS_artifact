#!/bin/bash
set -e # Exit on error

# --- Config ---
CGROUP_NAME="reporter_test"
CGROUP_BASE="/sys/fs/cgroup"
TARGET_NODE=0
CGROUP_PATH="$CGROUP_BASE/$CGROUP_NAME"
# --- End Config ---

# Check root and cgroupv2 mount
if [ "$(id -u)" -ne 0 ]; then echo "Error: Run as root." >&2; exit 1; fi
if ! findmnt -t cgroup2 | grep -q "$CGROUP_BASE"; then echo "Error: cgroup v2 not mounted at $CGROUP_BASE." >&2; exit 1; fi

# Create cgroup directory
mkdir -p "$CGROUP_PATH" || { echo "Error: Failed to create $CGROUP_PATH" >&2; exit 1; }

# Attempt to enable cpuset controller (ignore error if already enabled)
echo "+cpuset" > "$CGROUP_BASE/cgroup.subtree_control" 2>/dev/null || true
# Verify cpuset is actually enabled now
if ! grep -q "cpuset" "$CGROUP_BASE/cgroup.subtree_control"; then
    echo "Error: Cannot enable 'cpuset' controller in root." >&2
    rmdir "$CGROUP_PATH" 2>/dev/null || true # Cleanup
    exit 1
fi

# Find CPUs for the target node
NODE_CPUS=$(lscpu -p=NODE,CPU | grep "^${TARGET_NODE}," | cut -d, -f2 | paste -sd,)
if [ -z "$NODE_CPUS" ]; then
    echo "Error: No CPUs found for NUMA node $TARGET_NODE." >&2
    rmdir "$CGROUP_PATH" 2>/dev/null || true # Cleanup
    exit 1
fi

# Configure cpuset.cpus and cpuset.mems
echo "$NODE_CPUS" > "$CGROUP_PATH/cpuset.cpus" || { echo "Error: Failed to set cpuset.cpus" >&2; rmdir "$CGROUP_PATH" 2>/dev/null || true; exit 1; }
echo "$TARGET_NODE" > "$CGROUP_PATH/cpuset.mems" || { echo "Error: Failed to set cpuset.mems" >&2; rmdir "$CGROUP_PATH" 2>/dev/null || true; exit 1; }

echo "Successfully created cgroup '$CGROUP_NAME' ($CGROUP_PATH)"
echo " -> cpuset.cpus: $(cat $CGROUP_PATH/cpuset.cpus)"
echo " -> cpuset.mems: $(cat $CGROUP_PATH/cpuset.mems)"
exit 0
