#!/usr/bin/env python3
"""
Simple proportional controller for server-level power.

  • Reads the instantaneous system power from IPMI
  • Reads the target budget from ./budget   (first line, integer watts)
  • Computes the error  (actual − budget)
  • Reduces CPU power by Kp · error, but only in discrete steps that
    exist in policy.csv
  • Applies the corresponding core-count mask, CPU bandwidth limit
    and RAPL power cap – *only* when those values differ from the
    last settings.
"""

import csv, os, time, subprocess, signal, sys
from pathlib import Path
import subprocess, json, time, tempfile

# ----------------------------------------------------------------------
# ----------------  CONFIG -------------------------------------------------

MiB = 1024 * 1024
IOSTAT = ["./scripts/rpc.py", "bdev_get_iostat"] # Assuming in the same directory as SPDK

# POLICY_FILE       = Path("policy.csv")
# BUDGET_FILE       = Path("budget")
POLICY_FILE       = Path("./policy.csv")
BUDGET_FILE       = Path("./budget")    # Get power budget from local file
CTRL_PERIOD_SEC   = 1.0           # control interval
INITIAL_CPU_POWER = 210           # starting point (W)
SPDK_CORES        = 8              # number of SPDK cores (0..7)

HIGH_THRESHOLD    = 1.05          # 5% over budget
NO_ACTION_THRESHOLD = 0.98        # 2% under budget

HIGH_CPU_PROPORTION = 0.6    # 80% of CPU for power decrease
LOW_CPU_PROPORTION  = 0.3    # 50% of CPU for power decrease
BELOW_CPU_PROPORTION = 0.5    # 50% of CPU for power increase

# SSD model (single SSD)
WATT_READ = 7
WATT_WRITE = 10
READ_BANDWIDTH_MIB = 7000
WRITE_BANDWIDTH_MIB = 3600
WATT_PER_READ_MIB = WATT_READ / READ_BANDWIDTH_MIB
WATT_PER_WRITE_MIB = WATT_WRITE / WRITE_BANDWIDTH_MIB

# SSD config
NUM_SSD = 10

# ----------------------------------------------------------------------
# ----------  CONTROL ACTORS  ---------------------------
def get_instant_bandwidth(interval: float = 1.0):
    """
    Measure aggregate SSD bandwidth over `interval` seconds
    using exactly two RPC calls.

    Returns a 5-tuple:
        (total_MiB_s, read_MiB_s, write_MiB_s, raw_read_MiB_s, raw_write_MiB_s)
    """

    def _totals():
        out   = subprocess.check_output(IOSTAT)
        bdevs = json.loads(out)["bdevs"]
        bdev_reads = [b["bytes_read"] for b in bdevs]
        bdev_writes = [b["bytes_written"] for b in bdevs]
        r = sum(bdev_reads)
        w = sum(bdev_writes)
        return r, w, bdev_reads, bdev_writes

    r0, w0, br0, bw0 = _totals()
    t0     = time.perf_counter()

    time.sleep(interval)

    r1, w1, br1, bw1 = _totals()
    dt     = time.perf_counter() - t0

    read_mib  = (r1 - r0) / MiB / dt
    write_mib = (w1 - w0) / MiB / dt
    for i in range(len(br0)):
        br1[i] = (br1[i] - br0[i]) / MiB / dt
        bw1[i] = (bw1[i] - bw0[i]) / MiB / dt
    return read_mib, write_mib, br1, bw1

def calculate_power() -> int:
    """Measure IPMI power and store values in the shared list 'samples'."""
    result = subprocess.run(
        ["ipmitool", "dcmi", "power", "reading"],
        capture_output=True,
        text=True
    )
    for line in result.stdout.splitlines():
        if "Instantaneous" in line:
            ipmi_power = int(line.split()[3])  # Assuming power value is the 4th field
            return ipmi_power

def set_ssd_bandwidth(read_mibs, write_mibs):
    """
    Set SSD bandwidth limit using SPDK bdev_set_qos_limit.
    The limit is set as a percentage of the total SSD bandwidth.
    """
    # # If read or write mib/s is 0, it means no change, so no rpc needed
    if len(read_mibs) != NUM_SSD or len(write_mibs) != NUM_SSD:
        raise ValueError("read_mibs and write_mibs must both have length NUM_SSD")

    # Build one QoS line per SSD that actually needs a change
    lines = []
    for idx in range(NUM_SSD):
        r_limit = int(read_mibs[idx])
        w_limit = int(write_mibs[idx])

        if r_limit == 0 and w_limit == 0:
            continue            # nothing to do for this SSD
        args = []
        if r_limit > 0:
            args.append(f"--r-mbytes-per-sec {r_limit}")
        if w_limit > 0:
            args.append(f"--w-mbytes-per-sec {w_limit}")

        if len(args) > 0:
            bdev = f"Nvme{idx}n1"   # adapt to your naming scheme
            lines.append(f"bdev_set_qos_limit {bdev} " + " ".join(args))

    if not lines:               # every limit was 0 → nothing to change
        return

    # Batch-execute via stdin to a single rpc invocation
    with tempfile.NamedTemporaryFile("w", delete=False) as tf:
        tf.write("\n".join(lines) + "\n")
        tf.flush()
        print("\n".join(lines) + "\n")
        subprocess.run("./scripts/rpc.py", stdin=open(tf.name), text=True, check=True)
    os.unlink(tf.name)

def set_ssd_unlimited():
    """
    Set SSD bandwidth limit to unlimited using SPDK bdev_set_qos_limit.
    """
    # Build one QoS line per SSD that actually needs a change
    lines = []
    for idx in range(NUM_SSD):
        bdev = f"Nvme{idx}n1"   # adapt to your naming scheme
        lines.append(f"bdev_set_qos_limit {bdev} --r-mbytes-per-sec 0 --w-mbytes-per-sec 0")

    # Batch-execute via stdin to a single rpc invocation
    with tempfile.NamedTemporaryFile("w", delete=False) as tf:
        tf.write("\n".join(lines) + "\n")
        tf.flush()
        subprocess.run("./scripts/rpc.py", stdin=open(tf.name), text=True, check=True)
    os.unlink(tf.name)

def set_cpu_powercap(cpu_powercap: int):
    """Set RAPL powercap for power target on CPU"""
    result = subprocess.run(
            ["powercap-set", "intel-rapl", "-z", "0", "-c", "1", "-l", f"{cpu_powercap}000000"],
            capture_output=False
        )

def set_cpu_bandwidth(limit_percentage: int):
    """
    Set CPU bandwidth limit for the application cgroup.
    The limit is set as a percentage of the total CPU bandwidth.
    """
    # Define the path to the cgroup v2
    cgroup_path = '/sys/fs/cgroup/'

    # Create a new cgroup for the application if it doesn't exist
    app_cgroup = os.path.join(cgroup_path, 'user')

    # Calculate the percentage to be used
    conf_str = str(int(1000000 * limit_percentage / 100)) + " 1000000"

    # Set the cpuset.cpus for the application cgroup
    with open(os.path.join(app_cgroup, 'cpu.max'), 'w') as f:
        f.write(conf_str)

def set_spdk_cpumask(num_cores: int):
    """
    Tell every SPDK thread (ID 1‑SPDK_CORES+1) to run on the lowest num_cores CPUs.
    Example:
        num_cores = 3  -> mask 0x7  (binary 0b0000_0111)
    """
    if num_cores < 1 or num_cores > SPDK_CORES:
        raise ValueError(f"num_cores must be between 1 and {SPDK_CORES}")
    mask_hex = format((1 << num_cores) - 1, 'x')      # 1‑>1, 2‑>3, 3‑>7, …
    for tid in range(1, SPDK_CORES+2):                           # IDs 1..9
        subprocess.run(
            ["/home/dedongx/power_aware_storage/scripts/rpc.py", "thread_set_cpumask",
             "--cpumask", mask_hex, "--id", str(tid)],
            capture_output=False
        )

def load_policy(path: Path):
    """
    Return a list of rows sorted by *ascending* CPU power.
    Each row is a dict  {power, cores, bandwidth, rapl}
    """
    with path.open() as f:
        reader = csv.DictReader(f, skipinitialspace=True)
        rows   = []
        for row in reader:
            rows.append({
                "power"     : int(row["power"]),
                "cores"     : int(row["cores"]),
                "bandwidth" : int(row["bandwidth"]),
                "rapl"      : int(row["rapl"]),
            })
    # ascending order ⇒ rows[0] = lowest-power policy
    return sorted(rows, key=lambda r: r["power"])

POLICY = load_policy(POLICY_FILE)

def find_policy_for(target_cpu_power: int):
    """
    Pick the *highest* policy that is ≤ target_cpu_power.
    Falls back to the lowest-power policy if the target is below table range.
    """
    eligible = [p for p in POLICY if p["power"] <= target_cpu_power]
    return eligible[-1] if eligible else POLICY[0]

def execute_cpu_policy(current_policy, current_cpu_power, target_cpu_power):
    """
    Apply the given policy to the system.
    """
    # Find the next policy
    next_policy      = find_policy_for(target_cpu_power)

    # Apply policy if anything changed
    if (current_policy is None) or any(
            next_policy[k] != current_policy.get(k)
            for k in ("cores", "bandwidth", "rapl")):

        print(f"[controller] -> apply policy {next_policy}")

        if current_policy is None or next_policy["rapl"] != current_policy["rapl"]:
            set_cpu_powercap(next_policy["rapl"])

        if current_policy is None or next_policy["cores"] != current_policy["cores"]:
            set_spdk_cpumask(next_policy["cores"])

        if current_policy is None or next_policy["bandwidth"] != current_policy["bandwidth"]:
            set_cpu_bandwidth(next_policy["bandwidth"])

        current_policy   = next_policy
        current_cpu_power = next_policy["power"]
    return current_policy, current_cpu_power

def proportional_control():
    current_policy = None         # None: nothing applied yet
    current_cpu_power = INITIAL_CPU_POWER
    # Set initial CPU power
    set_cpu_powercap(280)
    set_spdk_cpumask(SPDK_CORES)
    set_cpu_bandwidth(100)        # 100% CPU bandwidth
    set_ssd_unlimited()           # unlimited SSD bandwidth
    ssd_limited = False

    while True:
        try:
            actual_power  = float(calculate_power())
            with BUDGET_FILE.open() as f:
                budget = int(f.readline().strip())
                high_bar = budget * HIGH_THRESHOLD
                no_action = budget * NO_ACTION_THRESHOLD
        except Exception as e:
            print(f"[controller] error reading sensors/files: {e}", file=sys.stderr)
            time.sleep(CTRL_PERIOD_SEC)
            continue

        diff_power = actual_power - budget         # (+) means we are *over* budget
        print(f"[controller] system power={actual_power:5.1f} W, "
              f"budget={budget} W, diff={diff_power:+5.1f} W, ", f"policy={current_policy}")

        # Calculate target CPU power
        target_cpu_power = current_cpu_power
        if actual_power > high_bar:
            # We are over budget, reduce CPU power
            target_cpu_power = current_cpu_power - diff_power * HIGH_CPU_PROPORTION
        elif actual_power > budget:
            # We are still over budget, but not too much
            target_cpu_power = current_cpu_power - diff_power * LOW_CPU_PROPORTION
        elif actual_power < no_action:
            # We are under budget, but not too much
            target_cpu_power = current_cpu_power - diff_power * BELOW_CPU_PROPORTION
        print(f"[controller] CPU power: current: {current_cpu_power} W target: {target_cpu_power} W")
        
        # Only if we want to change, we change
        if target_cpu_power != current_cpu_power:
            # Based on if we want to change CPU power, we do the following:
            pre_change_cpu_power = current_cpu_power
            # We need to monitor SSD bandwidth
            if target_cpu_power < 110:
                before_read_mib, before_write_mib, before_read_all_mib, before_write_all_mib = get_instant_bandwidth(0.5)

            # We need to change CPU power
            current_policy, current_cpu_power = execute_cpu_policy(
                current_policy, current_cpu_power, target_cpu_power
            )
            time.sleep(0.5)  # Give some time to the system to stabilize

            if target_cpu_power < 110:
                # We monitor SSD bandwidth again: if throttle/unthrottle SSD has better performance, we execute SSD first.
                after_read_mib, after_write_mib, after_read_all_mib, after_write_all_mib = get_instant_bandwidth(0.5)
                delta_read_mib = after_read_mib - before_read_mib
                delta_write_mib = after_write_mib - before_write_mib
                # SSD delta power
                ssd_delta_power = delta_read_mib * WATT_PER_READ_MIB * NUM_SSD + delta_write_mib * WATT_PER_WRITE_MIB * NUM_SSD
                # When delta power < 0, we are reducing power
                if ssd_delta_power < 0 and ssd_delta_power < diff_power:
                    # We should simply change SSD power instead of CPU power
                    # Throttle SSDs
                    # print(f"[controller] -> throttle SSDs")
                    ssd_read_mibs = [0] * NUM_SSD
                    ssd_write_mibs = [0] * NUM_SSD
                    for i in range(NUM_SSD):
                        if delta_read_mib < 0:
                            ssd_read_mibs[i] = after_read_all_mib[i] - 0.5 * delta_read_mib / NUM_SSD
                        if delta_write_mib < 0:
                            ssd_write_mibs[i] = after_write_all_mib[i] - 0.5 * delta_write_mib / NUM_SSD
                    # Set SSD bandwidth limit
                    print(f"[controller] set SSD bandwidth limit: {ssd_read_mibs}, {ssd_write_mibs}")
                    set_ssd_bandwidth(ssd_read_mibs, ssd_write_mibs)
                    ssd_limited = True
                    # Unthrottle CPU
                    current_policy, current_cpu_power = execute_cpu_policy(
                        current_policy, current_cpu_power, pre_change_cpu_power
                    )
                if ssd_delta_power > 0:
                    # We should unthrottle SSDs if not already
                    # Unthrottle SSDs
                    set_ssd_unlimited()
                    ssd_limited = False
            if ssd_limited:
                set_ssd_unlimited()
                ssd_limited = False
        time.sleep(CTRL_PERIOD_SEC)

def main():
    def handle_sigterm(sig, frame):
        print("\n[controller] terminating …")
        sys.exit(0)

    signal.signal(signal.SIGINT,  handle_sigterm)
    signal.signal(signal.SIGTERM, handle_sigterm)
    proportional_control()

if __name__ == "__main__":
    main()
