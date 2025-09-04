#!/bin/bash
for i in {1..10}; do
	echo "executing find /mnt/test_disk_${i}/ -maxdepth 1 -type f -exec rm -f {} + "
	find "/mnt/test_disk_${i}/" -maxdepth 1 -type f -exec rm -f {} + 
done

echo "All 10 disk's existing files have been removed"
