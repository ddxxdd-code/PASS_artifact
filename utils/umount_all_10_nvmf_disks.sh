#!/bin/bash

# Script to umount disks.

# Number of disks
DISK_COUNT=10

# Mount point prefix
MOUNT_BASE="/mnt/test_disk_"

# Iterate through disks 1 to 10
for i in $(seq 1 $DISK_COUNT); do
	umount "${MOUNT_BASE}${i}"
done

echo "All test disks unmounted"
