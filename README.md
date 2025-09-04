# PASS_evaluation_scripts

## How to run scripts
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

Then run YCSB workloads.
