# PASS Artifact
Artifact package of the paper PASS: A Power Adaptive Storage Server

## Purpose
This repository contains implementation of PASS. Specifically, the offline-profiling part and the online controller.

## Installation Guide
PASS is designed to use with (SPDK)[https://spdk.io/]. Please first install SPDK from source then put the PASS online controller (powercap\_PASS\_profiled.py) to under the directory of SPDK.

To run PASS's offline profiler, follow instructions in the cpu\_model directory to run offline profile of CPU.

## Usage
After starting SPDK application and add SPDK's PID to cgroup at `/sys/fs/cgroup/user/cgroup.procs` (we assume the cgroup is called user here, change accordingly if needed), run PASS online controller with `sudo`.

Update power budget to a file reside in the same directory as PASS online controller to control system power.

## System Requirement
PASS assumes RAPL power limit exists.

## Running Experiments
We provide scripts to run all experiments automatically.

## Notes on running scripts for benchmarks
### Fio

Put client and server side scripts on client and server. Change permissions on server side scripts so that can be run as SU when SSH into the server.

Start SPDK nvme-of target on server.

Run client-side script. This will make fio outputs and statistics on client side and collect system and CPU power on server.

### Before application benchmarks
Make Ext4 file systems on Nvme-oF disks on client side and mount the disks.

### Filebench
Install filebench on client.

Disable virtual address randomization by setting `/proc/sys/kernel/randomize_va_space`.

With `echo 0 | sudo tee  /proc/sys/kernel/randomize_va_space`.

### db_bench
Install Rocksdb.

Run scripts.

### YCSB
Install YCSB.

Run load_workload to populate database.


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