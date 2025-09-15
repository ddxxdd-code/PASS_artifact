#!/bin/bash

PM_PATH="/mnt/ramdisk"

for i in {0..9}; do
    BASE_BDEV="Nvme${i}n1"
    echo "Creating compress bdev for $BASE_BDEV"
    ./scripts/rpc.py bdev_compress_create --base_bdev "$BASE_BDEV" --pm_path "$PM_PATH"
done
