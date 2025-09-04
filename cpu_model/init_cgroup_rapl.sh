#!/bin/bash

# Script to create a cgroup v2 named 'poller_test', ensure required
# controllers are enabled in the parent, and initialize the cgroup.
# Requires root privileges.

CGROUP_NAME="poller_test"
CGROUP_PATH="/sys/fs/cgroup/${CGROUP_NAME}"
CGROUP_ROOT="/sys/fs/cgroup"

# --- Check if running as root ---
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi

# --- Check if cgroup v2 filesystem is mounted ---
if ! mount | grep -q 'type cgroup2'; then
    echo "Error: cgroup v2 filesystem not found at ${CGROUP_ROOT}."
    exit 1
fi

# --- Ensure required controllers are enabled in the parent cgroup ---
REQUIRED_CONTROLLERS=("cpu" "cpuset")
PARENT_SUBTREE_CONTROL="${CGROUP_ROOT}/cgroup.subtree_control"

echo "Checking and enabling required controllers (${REQUIRED_CONTROLLERS[*]}) in ${PARENT_SUBTREE_CONTROL}..."

# Check current enabled controllers in the parent
if [ ! -f "$PARENT_SUBTREE_CONTROL" ]; then
    echo "Error: Cannot find parent subtree control file: ${PARENT_SUBTREE_CONTROL}"
    exit 1
fi
ENABLED_CONTROLLERS=$(cat "${PARENT_SUBTREE_CONTROL}")

CONTROLLERS_TO_ENABLE=""
for controller in "${REQUIRED_CONTROLLERS[@]}"; do
    if ! echo "$ENABLED_CONTROLLERS" | grep -qw "$controller"; then
        echo "  Controller '${controller}' not found in parent, marking for enabling."
        CONTROLLERS_TO_ENABLE+="+${controller} " # Add with leading + and space
    else
        echo "  Controller '${controller}' already enabled in parent."
    fi
done

# Attempt to enable the missing controllers if any
if [ -n "$CONTROLLERS_TO_ENABLE" ]; then
    echo "Attempting to enable missing controllers: ${CONTROLLERS_TO_ENABLE}in ${PARENT_SUBTREE_CONTROL}"
    # Use sh -c to handle redirection with sudo privileges correctly
    # Use tee with append mode to avoid clobbering existing settings potentially made by other tools
    echo "${CONTROLLERS_TO_ENABLE}" | sudo tee -a "${PARENT_SUBTREE_CONTROL}" > /dev/null
    if [ $? -ne 0 ]; then
        echo "Error: Failed to enable controllers in ${PARENT_SUBTREE_CONTROL}."
        echo "Please try enabling them manually: sudo sh -c 'echo \"${CONTROLLERS_TO_ENABLE}\" >> ${PARENT_SUBTREE_CONTROL}'"
        exit 1
    fi
    echo "Successfully requested enabling controllers."
    # Re-read to confirm (optional, kernel might take a moment)
    # sleep 1 # Give kernel a moment
    # ENABLED_CONTROLLERS=$(cat "${PARENT_SUBTREE_CONTROL}")
    # echo "Current parent controllers: $ENABLED_CONTROLLERS"
else
    echo "All required controllers are already enabled in the parent."
fi

# --- Create the cgroup directory ---
if [ -d "${CGROUP_PATH}" ]; then
    echo "Cgroup '${CGROUP_NAME}' already exists at ${CGROUP_PATH}."
else
    echo "Creating cgroup '${CGROUP_NAME}' at ${CGROUP_PATH}..."
    mkdir "${CGROUP_PATH}"
    if [ $? -ne 0 ]; then
        echo "Error: Failed to create cgroup directory."
        exit 1
    fi
    echo "Cgroup created."
fi

# --- Initialize cgroup settings ---
# Now that controllers are expected to be enabled in the parent,
# the interface files should be present in the child cgroup.

echo "Initializing cgroup '${CGROUP_NAME}' settings..."

# 1. Set CPU bandwidth to maximum (no limit)
CPU_MAX_FILE="${CGROUP_PATH}/cpu.max"
if [ -f "$CPU_MAX_FILE" ]; then
    echo "Setting cpu.max to 'max 100000'..."
    echo "max 100000" > "${CPU_MAX_FILE}"
    if [ $? -ne 0 ]; then
        echo "Error: Failed to set cpu.max, despite controller supposedly being enabled."
        exit 1
    fi
else
    # This case should ideally not happen if controller enabling worked
    echo "Error: ${CPU_MAX_FILE} not found. Controller enabling might have failed silently or requires time."
    exit 1
fi

# 2. Set CPU affinity (cpuset.cpus) to all available effective CPUs
CPUSET_CPUS_FILE="${CGROUP_PATH}/cpuset.cpus"
if [ -f "$CPUSET_CPUS_FILE" ]; then
    EFFECTIVE_CPUS=$(cat "${CGROUP_ROOT}/cpuset.cpus.effective")
    if [ -z "$EFFECTIVE_CPUS" ]; then
         echo "Warning: Could not read effective CPUs from root cgroup. Cannot set cpuset.cpus."
    else
        echo "Setting cpuset.cpus to '${EFFECTIVE_CPUS}'..."
        echo "${EFFECTIVE_CPUS}" > "${CPUSET_CPUS_FILE}"
         if [ $? -ne 0 ]; then
            echo "Error: Failed to set cpuset.cpus, despite controller supposedly being enabled."
            exit 1
        fi
    fi
else
    echo "Error: ${CPUSET_CPUS_FILE} not found. Controller enabling might have failed silently or requires time."
    exit 1
fi

# 3. Set Memory node affinity (cpuset.mems) to all available effective memory nodes
CPUSET_MEMS_FILE="${CGROUP_PATH}/cpuset.mems"
if [ -f "$CPUSET_MEMS_FILE" ]; then
    EFFECTIVE_MEMS=$(cat "${CGROUP_ROOT}/cpuset.mems.effective")
    if [ -z "$EFFECTIVE_MEMS" ]; then
         echo "Warning: Could not read effective memory nodes from root cgroup. Cannot set cpuset.mems."
    else
        echo "Setting cpuset.mems to '${EFFECTIVE_MEMS}'..."
        echo "${EFFECTIVE_MEMS}" > "${CPUSET_MEMS_FILE}"
        if [ $? -ne 0 ]; then
            echo "Error: Failed to set cpuset.mems, despite controller supposedly being enabled."
            exit 1
        fi
    fi
else
     echo "Error: ${CPUSET_MEMS_FILE} not found. Controller enabling might have failed silently or requires time."
    exit 1
fi

# Must be run as root
for limit in /sys/class/powercap/intel-rapl*/*_power_limit_uw; do
    # Derive the corresponding max-power filename
    maxf="${limit%_power_limit_uw}_max_power_uw"
    if [[ -r "$maxf" && -w "$limit" ]]; then
        echo "Setting $(basename "$limit") → $(cat "$maxf") µW"
        cat "$maxf" > "$limit"
    fi
done

echo "Cgroup '${CGROUP_NAME}' creation and initialization finished successfully."
echo "  Path: ${CGROUP_PATH}"
echo "  cpu.max: $(cat ${CPU_MAX_FILE})"
echo "  cpuset.cpus: $(cat ${CPUSET_CPUS_FILE})"
echo "  cpuset.mems: $(cat ${CPUSET_MEMS_FILE})"
echo "Attempted to set RAPL limits to max."

exit 0

