# PASS Artifact Evaluation
This directory contains artifact for evaluating the PASS system described in the paper: PASS: A Power Adaptive Storage Server.

The artifact includes the following components:
- The offline CPU profiler of PASS to generate CPU control policies in `cpu_model`.
- The online controller of PASS to enforce power budgets in `online_controller`.
- Evaluation scripts in `pass_fio_experiments` and `pass_application_benchmarks` to run benchmarks and collect results.

## Evaluation instructions
The artifact provides scripts to run experiments and collect results for all results presented in the paper.

There are two options to evaluate the artifact:
1. Run experiments all at once using `run_all_experiments.sh`.
2. Run individual scripts in `pass_fio_experiments` and `pass_application_benchmarks` to run specific benchmarks.

The time estimated to run all experiments is around 12 hours. We encourage evaluators to run all experiments at once to save time and use applications like `tmux` to manage the long-running processes.

For each experiment, the script will run benchmarks with example input and configuration for each experiment presented in the paper and collect results automatically. The results will be saved in the corresponding directories. There is a referential output file for each experiment. The referential output files are listed in the `<experiment>_ref.txt` files in the corresponding directories.

## Installation Guide
PASS is designed to use with (SPDK)[https://spdk.io/]. Please first install SPDK from source then put the PASS online controller (powercap_PASS_profiled.py) to under the directory of SPDK.

To run PASS's offline profiler, follow instructions in the cpu_model directory to run offline profile of CPU.

### Step-by-step installation
1. Prepare setup of two servers, one initiator (running workloads, like fio) and one storage target (with NVMe SSDs and running SPDK), make sure the network bandwidth between the machines are not bottlenecking storage.

2. On the target side:
- Install SPDk: Download SPDK source code from `https://github.com/spdk/spdk/archive/refs/tags/v23.09.zip` to get SPDK. Install SPDK with RDMA using `./configure --with-rdma && make -j$proc`
- Configure SPDK NVMe-oF target: follow the example configuration file of `nvmf_rdma_10_disk_static_config.json`, modify the PCIe address of disks and the socket of listening to reflect the setup of the target server (set disk PCI address based on `lspci` outputs and write the socket of listening at the IP address of the NIC on the machine that connects to the initiator).
- Install power control softwares: apt install powercap, cpupower, and perf (for RAPL reading).
- PASS offline profile: Use the PASS offline profiler in artifact package by running `cpu_model/run.sh` and take the final profiled CPU policy to the downloaded SPDK directory.
- PASS online controller: Put the `online_controller/powercap_PASS_profile_based.py` to the SPDK directory where policy resides. Modify the SSD model of read/write bandwidth and SSD idle and maximum power according to the type of SSD used on the target machine.
- Running SPDK NVMe-oF target + PASS: Setup SPDK by running `sudo ./script/setup.sh` in SPDK directory. Start SPDK NVMe-oF via RDMA using command `./build/bin/nvmf_tgt -c nvmf_rdma_10_disk_static_config.json -m 0xFF` to run with 8 cores. Then put the PID of the `nvmf_tgt` to a cgroup, default to `/sys/fs/cgroup/user/cgroup.procs`. Then put power budget, like 400W to `budget` file via "echo 400 > budget". Then running PASS online controller: "sudo python3 powercap_PASS_profile_based.py".

3. On the initiator side:
- Install software needed: nvme-cli, fio, filebench, RocksDB, YCSB
- Connect to NVMe-oF target: `sudo ./utils/connect_nvmf_target.sh spdk` (adjust the IP address to the IP address of the target nvmf_tgt listening on)
- Example: run fio experiments: Write fio job description file to use the newly attached NVMe-oF disks (change the fio job's filenema= to the attached remote disks). Then run `sudo fio experiment_config.fio` to issue workload. Similar for application benchmarks, only need to mount the disks and make filesystem on them before experiments.

## Usage
After starting SPDK application and add SPDK's PID to cgroup at `/sys/fs/cgroup/user/cgroup.procs` (we assume the cgroup is called user here, change accordingly if needed), run PASS online controller with `sudo`.

Update power budget to a file reside in the same directory as PASS online controller to control system power.

### Running Experiments
To run all experiments at once, run `run_all_experiments.sh` as `sudo`.

To run individual benchmarks, enter the `pass_fio_experiments` and `pass_application_benchmarks` directories to find directories named after figure numbers. For example, to run experiments for Figure 5, enter `pass_fio_experiments/fig5` and run `run_fig5.sh` as `sudo`.

### Example experiment output
#### Fio experiments
The output of running fio experiments looks like the following:
```
# Experiment script
$ sudo ./plot_figure1.sh

# Expected behavior
On standard output the script will run initilization cleanup, run benchmarks under Linux, then cleanup and start SPDK instance, then run benchmarks under SPDK of different power budgets by running PASS online contoller and thunderbolt.

# Expected last lines of output
Clean
Wrote 27 rows to latency_data.csv
Normalized results written to latency_data_normalized.csv
Plotting figure 1
[Done] figure 1 experiments finished
```

#### Application benchmarks
The output of running application benchmarks looks like the following:
```
# Experiment script
$ sudo ./plot_db_bench_results.sh

# Expected behavior
On standard output the script will run initilization cleanup, run benchmarks under Linux, then cleanup and start SPDK instance, then run benchmarks under SPDK of different power budgets by running PASS online contoller and thunderbolt.

# Expected last lines of output
Aggregated metrics written → pass_500/pass_db_bench_aggregated_metrics.csv
All combinations processed.
[collect] wrote 66 rows → db_bench_combined.csv
[PLOT] plot_db_bench_all_one_figure_insert_unlimited.py
/home/dedongx/PASS_AE/pass_application_benchmarks/db_bench/plot_db_bench_all_one_figure_insert_unlimited.py:101: UserWarning: FixedFormatter should only be used together with FixedLocator
  ax_unlimited.set_xticklabels(unlimited_labels, rotation=15)
Figure with throughput and non adaptive case saved as db_bench_throughput_with_unlimited_power_case.pdf.
[DONE] db_bench experiments completed.
```
The last line of output indicates that the experiments are completed successfully.

## System Requirement
### Hardware dependencies. 
To run experiments of PASS, two servers are needed and connected through 100Gbps and 200Gbps RDMA network.
**Target server**:
- 10 NVMe SSDs (3.84 TiB each)
- Intel Xeon Gold 6430 processor
- 256 GiB DDR5 memory
- 100 GbE and 200 GbE RDMA NICs (e.g. ConnectX-5 and ConnectX-6)
**Initiator server**:
- Intel Xeon Gold 6530 processor
- 100 GbE and 200 GbE RDMA NICs (e.g. ConnectX-5 and ConnectX-6)
### Software dependencies.
- OS: Ubuntu 22.04
- Kernel: Linux 5.15+ with NVMe over Fabrics and RDMA support
- SPDK: 23.09 with RDMA support
- Intel RAPL
- Programming Language: Python 3.10+
- Software: fio 3.38
- Other software: Filebench 1.4.9.1, RocksDB 9.8.0, YCSB
0.17.0

## Assumed Configuration
The SPDK configuration file assumes the target machine has 10 NVMe SSDs with corresponding PCI addresses as in `spdk.conf`. Please modify the configuration file if the target machine has different NVMe SSDs or PCI addresses.

It also assumes that the target machine listens on IP address `192.168.3.50` for NVMe-oF connections on port `4420`. Please modify the configuration file if a different IP address is used.

The minimum size needed for the disk is about 1 TiB while we recommend using larger disks like 3.84 TiB in our setup.

To run PASS, the SPDK 23.09+ version is needed. Please get the source of SPDK and compile with RDMA support.

## Citation
This is the artifact associated with the paper:
```
@inproceedings{pass2026eurosys,
  author    = {Xie, Dedong and Stavrinos, Theano and Park, Jonggyu and Peter, Simon and Kasikci, Baris and Anderson, Thomas},
  title     = {PASS: A Power-Adaptive Storage Server},
  booktitle = {EuroSys 2026},
  year      = {2026},
  note      = {To appear}
}