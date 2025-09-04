# PASS Artifact
Artifact package of the paper PASS: A Power Adaptive Storage Server

# Purpose
This repository contains implementation of PASS. Specifically, the offline-profiling part and the online controller.

# Installation Guide
PASS is designed to use with (SPDK)[https://spdk.io/]. Please first install SPDK from source then put the PASS online controller (powercap\_PASS\_profiled.py) to under the directory of SPDK.

To run PASS's offline profiler, follow instructions in the cpu\_model directory to run offline profile of CPU.

# Usage
After starting SPDK application and add SPDK's PID to cgroup at `/sys/fs/cgroup/user/cgroup.procs` (we assume the cgroup is called user here, change accordingly if needed), run PASS online controller with `sudo`.

Update power budget to a file reside in the same directory as PASS online controller to control system power.

# System Requirement
PASS assumes RAPL power limit exists.

# Citation
This is the artifact associated with the paper:
```
@inproceedings{pass2026eurosys,
  author    = {Xie, Dedong and Stavrinos, Theano and Park, Jonggyu and Peter, Simon and Kasikci, Baris and Anderson, Thomas},
  title     = {PASS: A Power-Adaptive Storage Server},
  booktitle = {EuroSys 2026},
  year      = {2026},
  note      = {To appear}
}
```
