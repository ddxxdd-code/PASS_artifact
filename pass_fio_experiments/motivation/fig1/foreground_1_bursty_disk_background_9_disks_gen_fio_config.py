#!/usr/bin/env python3
import argparse
from pathlib import Path

# ---------------- Global Template ----------------
GLOBAL_TEMPLATE = """[global]
ioengine=psync
direct=1
thread=1
time_based
runtime={runtime}
numjobs={numjobs}
iodepth=1
bs=4kb
rw=randwrite
allow_mounted_write=1
"""

# ---------------- Global Template for numjobs=0 ----------------
GLOBAL_TEMPLATE_NOJOBS = """[global]
ioengine=psync
direct=1
thread=1
time_based
runtime={runtime}
iodepth=1
allow_mounted_write=1
"""

# ---------------- Test Sections ----------------
TEST_SECTIONS = """[test_64kb_rwrite_5n2]
filename=/dev/nvme5n2

[test_64kb_rwrite_5n3]
filename=/dev/nvme5n3

[test_64kb_rwrite_5n4]
filename=/dev/nvme5n4

[test_64kb_rwrite_5n5]
filename=/dev/nvme5n5

[test_64kb_rwrite_5n6]
filename=/dev/nvme5n6

[test_64kb_rwrite_5n7]
filename=/dev/nvme5n7

[test_64kb_rwrite_5n8]
filename=/dev/nvme5n8

[test_64kb_rwrite_5n9]
filename=/dev/nvme5n9

[test_64kb_rwrite_5n10]
filename=/dev/nvme5n10
"""

# ---------------- Bursty Section ----------------
BURSTY_SECTION = """[bursty]
filename=/dev/nvme5n1
ioengine=psync
numjobs=16
iodepth=1
bs=4kb
rw=randwrite
thinktime=5s
thinktime_iotime=100ms
thinktime_blocks_type=issue
io_submit_mode=offload
rate_iops=3200
"""

def make_job_text(numjobs: int, runtime: int) -> str:
    if numjobs == 0:
        # Special case: only global (without numjobs/bs/rw) + bursty
        global_txt = GLOBAL_TEMPLATE_NOJOBS.format(runtime=runtime)
        return f"{global_txt}\n{BURSTY_SECTION}\n"
    else:
        # Normal case: global + tests + bursty
        global_txt = GLOBAL_TEMPLATE.format(runtime=runtime, numjobs=numjobs)
        return f"{global_txt}\n{TEST_SECTIONS}\n{BURSTY_SECTION}\n"

def main():
    ap = argparse.ArgumentParser(
        description="Generate fio job file with configurable numjobs (-n) and runtime (-t)."
    )
    ap.add_argument("-n", "--numjobs", type=int, default=5,
                    help="numjobs for [global] (default: 5)")
    ap.add_argument("-t", "--runtime", type=int, default=180,
                    help="runtime seconds for [global] (default: 180)")
    ap.add_argument("--prefix", type=str, default="fig1",
                    help="filename prefix (default: fig1)")
    args = ap.parse_args()

    outdir = Path.cwd()
    fname = outdir / f"{args.prefix}_rwrite_32k_9_disk_bursty_4k_1_disk_n{args.numjobs}_t{args.runtime}.fio"

    txt = make_job_text(args.numjobs, args.runtime)
    fname.write_text(txt)
    print(f"Wrote fio config to {fname}")

if __name__ == "__main__":
    main()
