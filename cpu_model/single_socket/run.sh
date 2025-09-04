#!/bin/bash
gcc poll_simul.c -pthread -O2 -march=native -Wno-unused-result -o poll_simul -lm
echo $$ > /sys/fs/cgroup/cgroup.procs
apt update -y; apt install -y cgroup-tools
make
./core_setup.sh all
./cgr_rpt.sh
./init_cgroup_rapl.sh
./run_simul.sh
make clean
