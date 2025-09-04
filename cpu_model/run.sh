#!/bin/bash
make
./core_setup.sh socket0
./init_cgroup_rapl.sh
./run_simul.sh
make clean
