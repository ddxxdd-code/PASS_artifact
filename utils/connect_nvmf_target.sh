#!/usr/bin/env bash

# Check if running as root (EUID 0)
if [ "$EUID" -ne 0 ]; then
  echo "This script must be run with sudo or as root."
  exit 1
fi

set -euo pipefail

case "${1:-}" in
  spdk)
    echo "Connecting to SPDK NVMe-oF target..."
    /usr/sbin/nvme connect -t rdma -n "nqn.2016-06.io.spdk:cnode1" -a 192.168.3.50 -s 4420
    ;;
    
  linux_nvmf)
    echo "Connecting to Linux NVMe-oF target..."
    /usr/sbin/nvme connect -t rdma -n nvme-subsystem -a 192.168.3.50 -s 4420
    ;;
    
  *)
    echo "Usage: $0 {spdk|linux_nvmf}"
    exit 1
    ;;
esac
