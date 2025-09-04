#!/bin/bash

# Script to configure the 'poller_test' cgroup v2:
# 1. Sets CPU affinity (cpuset.cpus) to a specific number of logical cores (CPU threads)
#    exclusively from SOCKET 1, prioritizing hyperthread siblings together from the
#    same physical core within that socket.
# 2. Sets CPU bandwidth limit (cpu.max) based on the number of assigned logical cores
#    and a percentage bandwidth.
# 3. Sets the RAPL power limit for socket 1 (intel-rapl:1) using constraint_0.
# 4. **Does NOT modify RAPL limits for other sockets.**
# 5. **Diagnostic**: Attempts to write the same limit to constraint_1 on socket 1, logging success/failure.
#
# Usage: ./configure_poller_cgroup_socket1.sh <num_logical_cores_on_socket1> <bandwidth_percentage> <rapl_limit_watts_socket1>
# Example: ./configure_poller_cgroup_socket1.sh 8 50 80 (Use 8 logical cores from socket 1, 50% bandwidth, limit socket 1 to 80W)
# Requires root privileges.

set -euo pipefail # Exit on error, unset variable, or pipe failure

# --- Configuration ---
CGROUP_NAME="poller_test"
CGROUP_PATH="/sys/fs/cgroup/${CGROUP_NAME}"
RAPL_BASE_PATH="/sys/class/powercap/intel-rapl"
TARGET_SOCKET_ID=1 # Define the target socket ID
CPU_PERIOD=100000 # Default cgroup cpu.max period (100ms)
CPU_INFO_CMD="lscpu -p=CPU,CORE,SOCKET" # Command to get topology

# --- Helper Functions ---
log_info() {
    echo "INFO: $1"
}

log_warn() {
    echo "WARN: $1" >&2
}

log_error() {
    echo "ERROR: $1" >&2
    exit 1
}

# --- Check Root ---
if [[ $EUID -ne 0 ]]; then
   log_error "This script must be run as root."
fi

# --- Validate Input Arguments ---
if [ "$#" -ne 3 ]; then
    echo "Usage: $0 <num_logical_cores_on_socket${TARGET_SOCKET_ID}> <bandwidth_percentage> <rapl_limit_watts_socket${TARGET_SOCKET_ID}>"
    echo "Example: $0 8 50 80"
    exit 1
fi

REQUESTED_CORES=$1
BANDWIDTH_PERCENTAGE=$2
RAPL_LIMIT_WATTS_SOCKET1=$3 # Renamed variable

# Validate numeric inputs
if ! [[ "$REQUESTED_CORES" =~ ^[0-9]+$ ]] || [ "$REQUESTED_CORES" -le 0 ]; then
    log_error "Number of logical cores must be a positive integer."
fi
if ! [[ "$BANDWIDTH_PERCENTAGE" =~ ^[0-9]+$ ]] || [ "$BANDWIDTH_PERCENTAGE" -lt 0 ] || [ "$BANDWIDTH_PERCENTAGE" -gt 100 ]; then
    log_error "Bandwidth percentage must be an integer between 0 and 100."
fi
# Validate RAPL limit - allow 0 Watts
if ! [[ "$RAPL_LIMIT_WATTS_SOCKET1" =~ ^[0-9]+$ ]]; then
    log_error "RAPL limit for Socket ${TARGET_SOCKET_ID} must be a non-negative integer (Watts)."
fi

# --- Check Cgroup Existence ---
if [ ! -d "${CGROUP_PATH}" ]; then
    log_error "Cgroup '${CGROUP_NAME}' does not exist at ${CGROUP_PATH}. Please create it first."
fi

# --- Determine CPU Topology and Select Cores from Socket 1 ---
log_info "Analyzing CPU topology to select cores exclusively from Socket ${TARGET_SOCKET_ID}, prioritizing hyperthread siblings..."

declare -A core_siblings # Associative array: core_siblings[Socket:Core]="cpu1,cpu2..."
declare -a sorted_physical_cores_all # Array to store "Socket:Core" strings for sorting across all sockets initially
declare -A socket_core_counts # Count cores per socket

# Use process substitution and a while loop for reliable line reading
while IFS=',' read -r cpu core socket _; do
    # Skip header/comment lines or lines missing data
    [[ "$cpu" =~ ^# ]] && continue
    [[ -z "$cpu" || -z "$core" || -z "$socket" ]] && continue

    coord="${socket}:${core}"

    # Initialize socket count if not present
    socket_core_counts[$socket]=$((${socket_core_counts[$socket]:-0} + 1))

    # Store sibling info regardless of socket for now
    if [[ ! ${core_siblings[$coord]+_} ]]; then
        # Key does not exist: Initialize the entry for this physical core
        core_siblings[$coord]="$cpu"
        sorted_physical_cores_all+=("$coord") # Add unique physical core coord to list
    else
        # Key exists: Append the new CPU ID to the existing list
        current_siblings=() # Initialize as empty array
        IFS=',' read -ra current_siblings <<< "${core_siblings[$coord]}"
        current_siblings+=("$cpu")
        # Sort the list of siblings numerically after adding the new one
        sorted_siblings_list=() # Initialize as empty array
        IFS=$'\n' sorted_siblings_list=($(printf "%s\n" "${current_siblings[@]}" | sort -n))
        unset IFS
        core_siblings[$coord]=$(IFS=,; echo "${sorted_siblings_list[*]}")
    fi
done < <($CPU_INFO_CMD)

# Check if we got any CPU info
if [ ${#core_siblings[@]} -eq 0 ]; then
    log_error "Could not parse CPU topology information from '$CPU_INFO_CMD'."
fi

# Check if target socket exists and has cores
if [[ -z ${socket_core_counts[$TARGET_SOCKET_ID]+_} ]] || [[ ${socket_core_counts[$TARGET_SOCKET_ID]} -eq 0 ]]; then
    log_error "Target Socket ${TARGET_SOCKET_ID} not found or has no cores according to '$CPU_INFO_CMD'."
fi

TOTAL_LOGICAL_CORES_ON_TARGET_SOCKET=${socket_core_counts[$TARGET_SOCKET_ID]}
log_info "Found ${TOTAL_LOGICAL_CORES_ON_TARGET_SOCKET} logical cores on target Socket ${TARGET_SOCKET_ID}."

# Check if requested cores exceed available cores on the target socket
if [ "$REQUESTED_CORES" -gt "$TOTAL_LOGICAL_CORES_ON_TARGET_SOCKET" ]; then
    log_error "Requested ${REQUESTED_CORES} cores, but only ${TOTAL_LOGICAL_CORES_ON_TARGET_SOCKET} logical cores are available on Socket ${TARGET_SOCKET_ID}."
fi

# Sort all physical cores primarily by socket, secondarily by core ID
# Use printf and sort for robust sorting of "Socket:Core" strings
IFS=$'\n' sorted_physical_cores_all=($(printf "%s\n" "${sorted_physical_cores_all[@]}" | sort -t ':' -k1,1n -k2,2n))
unset IFS

# Select logical cores, prioritizing siblings, ONLY from the target socket
SELECTED_LOGICAL_CPUS=()
cores_selected_count=0

log_info "Selecting ${REQUESTED_CORES} logical cores from Socket ${TARGET_SOCKET_ID}..."

for coord in "${sorted_physical_cores_all[@]}"; do
    # Extract socket ID from coordinate
    socket_id=$(echo "$coord" | cut -d':' -f1)

    # Skip if not the target socket
    if [[ "$socket_id" -ne "$TARGET_SOCKET_ID" ]]; then
        continue
    fi

    # Get the logical CPUs (siblings) for this physical core on the target socket
    IFS=',' read -ra siblings <<< "${core_siblings[$coord]}"
    num_siblings=${#siblings[@]}

    # How many more cores do we need?
    cores_needed=$(( REQUESTED_CORES - cores_selected_count ))

    if [ $cores_needed -le 0 ]; then
        break # We have enough cores
    fi

    log_info "  Considering physical core ${coord} (Socket ${socket_id}) with siblings: ${siblings[*]}"

    if [ "$num_siblings" -le "$cores_needed" ]; then
        # Add all siblings from this physical core
        SELECTED_LOGICAL_CPUS+=("${siblings[@]}")
        cores_selected_count=$(( cores_selected_count + num_siblings ))
        log_info "    -> Added all ${num_siblings} siblings. Total selected: ${cores_selected_count}"
    else
        # Add only the needed number of siblings from this physical core
        # Siblings are already sorted numerically from the parsing step
        needed_siblings=("${siblings[@]:0:$cores_needed}")
        SELECTED_LOGICAL_CPUS+=("${needed_siblings[@]}")
        cores_selected_count=$(( cores_selected_count + cores_needed ))
        log_info "    -> Added ${cores_needed} siblings (${needed_siblings[*]}). Total selected: ${cores_selected_count}"
        break # We have exactly the number requested
    fi
done

# Verify we selected the correct number (should always match if logic is correct)
if [ "$cores_selected_count" -ne "$REQUESTED_CORES" ]; then
    # This indicates a logic error or insufficient available cores (already checked earlier)
    log_error "Internal error: Selected ${cores_selected_count} cores, but requested ${REQUESTED_CORES} from Socket ${TARGET_SOCKET_ID}."
fi

# Sort the final list numerically for cpuset.cpus
IFS=$'\n' sorted_selected_cpus=($(printf "%s\n" "${SELECTED_LOGICAL_CPUS[@]}" | sort -n))
unset IFS
CPUSET_CPUS_VALUE=$(IFS=,; echo "${sorted_selected_cpus[*]}") # Join with commas

log_info "Final selected logical cores (${#sorted_selected_cpus[@]}) from Socket ${TARGET_SOCKET_ID}: ${CPUSET_CPUS_VALUE}"

# --- Apply cpuset.cpus setting ---
log_info "Attempting to write '${CPUSET_CPUS_VALUE}' to ${CGROUP_PATH}/cpuset.cpus"
if ! echo "${CPUSET_CPUS_VALUE}" | sudo tee "${CGROUP_PATH}/cpuset.cpus" > /dev/null; then
     log_error "Failed to write to ${CGROUP_PATH}/cpuset.cpus. Check permissions and dmesg."
fi
log_info "Successfully wrote to ${CGROUP_PATH}/cpuset.cpus"


# --- Calculate and apply cpu.max setting ---
log_info "Calculating cpu.max..."

# Calculate quota based on the number of *assigned logical cores* and the percentage
# Note: We use REQUESTED_CORES here, which should match ${#sorted_selected_cpus[@]}
CPU_QUOTA=$(( REQUESTED_CORES * BANDWIDTH_PERCENTAGE * CPU_PERIOD / 100 ))

# Handle edge cases for quota
if [ "$BANDWIDTH_PERCENTAGE" -eq 0 ]; then
    CPU_QUOTA=0
    log_warn "Bandwidth set to 0%. Processes may receive no CPU time."
elif [ "$CPU_QUOTA" -le 0 ] && [ "$BANDWIDTH_PERCENTAGE" -gt 0 ]; then
     CPU_QUOTA=1 # Minimum positive quota if percentage > 0
     log_warn "Calculated quota is very low (<1us), setting minimum positive quota (1us)."
fi

# Format cpu.max value ("max" or "quota period")
if [ "$BANDWIDTH_PERCENTAGE" -eq 100 ]; then
    CPU_MAX_VALUE="max ${CPU_PERIOD}"
else
    CPU_MAX_VALUE="${CPU_QUOTA} ${CPU_PERIOD}"
fi

log_info "Calculated cpu.max: ${CPU_MAX_VALUE} (Quota: ${CPU_QUOTA}us, Period: ${CPU_PERIOD}us)"
log_info "Attempting to write '${CPU_MAX_VALUE}' to ${CGROUP_PATH}/cpu.max"
if ! echo "${CPU_MAX_VALUE}" | sudo tee "${CGROUP_PATH}/cpu.max" > /dev/null; then
     log_error "Failed to write to ${CGROUP_PATH}/cpu.max. Check permissions and dmesg."
fi
log_info "Successfully wrote to ${CGROUP_PATH}/cpu.max"


# --- Apply RAPL power limits ONLY TO SOCKET 1 ---
log_info "Configuring RAPL power limits for Socket ${TARGET_SOCKET_ID} only..."

# Check if base RAPL path exists
if [ ! -d "$RAPL_BASE_PATH" ]; then
    log_warn "Base RAPL directory not found at ${RAPL_BASE_PATH}. Skipping RAPL configuration."
else
    # Construct the specific path for the target socket
    target_socket_rapl_path="${RAPL_BASE_PATH}/intel-rapl:${TARGET_SOCKET_ID}"

    if [ ! -d "$target_socket_rapl_path" ]; then
        log_warn "RAPL interface for target Socket ${TARGET_SOCKET_ID} (intel-rapl:${TARGET_SOCKET_ID}) not found at ${target_socket_rapl_path}. Skipping RAPL configuration for this socket."
    else
        socket_name=$(basename "$target_socket_rapl_path") # e.g., intel-rapl:1
        log_info "Processing RAPL for target ${socket_name}..."

        # Check/Enable RAPL interface for the target socket
        enabled_file="${target_socket_rapl_path}/enabled"
        if [ -f "$enabled_file" ]; then
            # Check if reading the file fails (e.g., permissions)
            is_enabled=$(cat "$enabled_file" 2>/dev/null)
            if [ $? -ne 0 ]; then
                log_warn "  Could not read enabled status from ${enabled_file}. Assuming enabled."
            elif [[ "$is_enabled" == "0" ]]; then
                log_info "  Attempting to enable RAPL for ${socket_name}..."
                # Use tee for writing as root
                if ! echo 1 | sudo tee "$enabled_file" > /dev/null; then
                    log_warn "  Failed to enable RAPL for ${socket_name}. Power limits may not apply."
                else
                    log_info "  Successfully enabled RAPL for ${socket_name}."
                    sleep 0.1 # Short pause
                fi
            fi
        else
            log_warn "  Cannot find enabled file at ${enabled_file}. Assuming enabled."
        fi

        # Determine target power limit (uW) for Socket 1
        target_limit_uw=$(( RAPL_LIMIT_WATTS_SOCKET1 * 1000000 ))
        target_limit_w=$RAPL_LIMIT_WATTS_SOCKET1
        log_info "  Target Socket ${TARGET_SOCKET_ID}: Target limit ${target_limit_w}W (${target_limit_uw}uW)"

        # --- Set Constraint 0 for Socket 1 ---
        constraint0_file="${target_socket_rapl_path}/constraint_0_power_limit_uw"
        if [ -f "$constraint0_file" ]; then
             # Use tee for writing as root
             log_info "  Attempting to set Constraint 0 limit to ${target_limit_uw}uW"
             if ! echo "${target_limit_uw}" | sudo tee "${constraint0_file}" > /dev/null; then
                 log_warn "  Failed to write Constraint 0 limit to ${constraint0_file}. Check dmesg."
             else
                 log_info "  Successfully set Constraint 0 limit."
             fi
        else
             log_warn "  Constraint 0 file not found at ${constraint0_file}. Skipping."
        fi

        # --- DIAGNOSTIC: Set Constraint 1 for Socket 1 ---
        constraint1_file="${target_socket_rapl_path}/constraint_1_power_limit_uw"
        if [ -f "$constraint1_file" ]; then
             # Use tee for writing as root
             log_info "  Attempting diagnostic write to Constraint 1 (${target_limit_uw}uW)"
             if ! echo "${target_limit_uw}" | sudo tee "${constraint1_file}" > /dev/null; then
                   log_warn "  Diagnostic write to Constraint 1 (${constraint1_file}) failed."
             else
                   log_info "  Diagnostic write to Constraint 1 succeeded."
             fi
        else
             log_info "  Constraint 1 file not found at ${constraint1_file}. Skipping diagnostic write."
        fi
    fi # End check if target socket RAPL path exists
fi # End check if base RAPL path exists

# --- Configuration Summary ---
echo "--- Configuration Summary ---"
echo "Cgroup:           ${CGROUP_PATH}"
# Read values directly from files for verification
cpuset_val=$(cat "${CGROUP_PATH}/cpuset.cpus" 2>/dev/null || echo "Error reading")
cpumax_val=$(cat "${CGROUP_PATH}/cpu.max" 2>/dev/null || echo "Error reading")
echo "cpuset.cpus:      ${cpuset_val} (Targeted Socket ${TARGET_SOCKET_ID})"
echo "cpu.max:          ${cpumax_val}"
echo "RAPL Limits (Current Values - Only Socket ${TARGET_SOCKET_ID} was targeted):"
if [ -d "$RAPL_BASE_PATH" ]; then
    shopt -s nullglob
    rapl_sockets_final=( ${RAPL_BASE_PATH}/intel-rapl:[0-9]* )
    shopt -u nullglob
    if [ ${#rapl_sockets_final[@]} -gt 0 ]; then
        for socket_path_final in "${rapl_sockets_final[@]}"; do
             socket_name_final=$(basename "$socket_path_final")
             socket_id_final="${socket_name_final##*:}" # Extract number after colon
             echo "  Socket: ${socket_name_final}"
             if [[ "$socket_id_final" -eq "$TARGET_SOCKET_ID" ]]; then
                 echo "    (This socket was targeted by the script)"
             else
                 echo "    (This socket was NOT targeted by the script)"
             fi

             for constraint_num in 0 1; do
                 constraint_file="${socket_path_final}/constraint_${constraint_num}_power_limit_uw"
                 if [ -f "$constraint_file" ]; then
                     # Read requires root, but cat might work depending on perms
                     limit_uw=$(cat "${constraint_file}" 2>/dev/null)
                     if [[ "$limit_uw" =~ ^[0-9]+$ ]]; then
                         limit_w=$(( limit_uw / 1000000 ))
                         echo "    Constraint ${constraint_num} Limit: ${limit_uw} uW (${limit_w} W)"
                     else
                         echo "    Constraint ${constraint_num} Limit: Could not read (Permissions?)."
                     fi
                 else
                     echo "    Constraint ${constraint_num} Limit: File not found."
                 fi
             done
        done
    else
        echo "  No RAPL interfaces found to report."
    fi
else
    echo "  RAPL base path not found."
fi
echo "---------------------------"
log_info "Configuration complete."

exit 0

