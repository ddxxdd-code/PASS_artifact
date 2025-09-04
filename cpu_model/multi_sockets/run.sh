#!/bin/bash
echo $$ > /sys/fs/cgroup/cgroup.procs
apt update -y; apt install -y cgroup-tools
make
./core_setup.sh all
./cgr_rpt.sh
./init_cgroup_rapl.sh
./run_simul.sh
make clean
