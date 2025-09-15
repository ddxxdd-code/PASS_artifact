#!/bin/bash

for i in {0..9}; do
    COMP_BDEV="COMP_Nvme${i}n1"
    echo "Deleting compress bdev $COMP_BDEV"
    ./scripts/rpc.py bdev_compress_delete "$COMP_BDEV"
done
