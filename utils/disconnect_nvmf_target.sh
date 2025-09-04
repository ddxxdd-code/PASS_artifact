#!/usr/bin/env bash

# Check if running as root (EUID 0)
if [ "$EUID" -ne 0 ]; then
  echo "This script must be run with sudo or as root."
  exit 1
fi

set -euo pipefail

case "${1:-}" in
  spdk)
    echo "Disconnecting from SPDK NVMe-oF target..."
    nvme disconnect -n "nqn.2016-06.io.spdk:cnode1"
    ;;
    
  linux_nvmf)
    echo "Disconnecting from Linux NVMe-oF target..."
    nvme disconnect -n nvme-subsystem
    ;;
    
  *)
    echo "Usage: $0 {spdk|linux_nvmf}"
    exit 1
    ;;
esac
