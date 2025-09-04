#!/bin/bash

# Script to create ext4 filesystem and mount disks, or mount if filesystem exists.

# Number of disks
DISK_COUNT=10

# Base disk name and mount point prefix
DISK_BASE="nvme5n"
MOUNT_BASE="/mnt/test_disk_"

# Iterate through disks 1 to 10
for i in $(seq 1 $DISK_COUNT); do
    DISK="/dev/${DISK_BASE}${i}"
    MOUNT_POINT="${MOUNT_BASE}${i}"

    echo "Processing disk: $DISK"

    # Check if the disk exists
    if [ ! -b "$DISK" ]; then
        echo "Disk $DISK does not exist. Skipping..."
        continue
    fi

    # Create the mount point if it doesn't exist
    if [ ! -d "$MOUNT_POINT" ]; then
        echo "Creating mount point: $MOUNT_POINT"
        mkdir -p "$MOUNT_POINT"
    fi

    # Check for existing filesystem
    FS_TYPE=$(blkid -o value -s TYPE "$DISK")

    if [ -n "$FS_TYPE" ]; then
        echo "Existing filesystem detected on $DISK: $FS_TYPE. Mounting..."
    else
        echo "No filesystem found on $DISK. Creating ext4 filesystem..."
        mkfs.ext4 -F "$DISK"
    fi

    # Mount the disk
    mount "$DISK" "$MOUNT_POINT"

    # Check if mount was successful
    if [ $? -eq 0 ]; then
        echo "$DISK mounted successfully on $MOUNT_POINT"
    else
        echo "Failed to mount $DISK on $MOUNT_POINT"
    fi

    # Change folder permission to 777
    chmod 777 "$MOUNT_POINT" 
done

echo "All disks processed."
