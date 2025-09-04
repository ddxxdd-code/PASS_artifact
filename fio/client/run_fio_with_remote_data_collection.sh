#!/bin/bash

# Function to display usage
usage() {
  cat <<EOF
Usage: $0 [-u <remote_user>] [-ip <remote_ip>] [-path <remote_script_path>] [-c <fio_config>] [-d <log_directory>] [-o <log_output>]
  -u, --remote-user       Remote user to SSH (default: dedongx)
  -ip, --remote-ip        Remote IP address (default: 192.168.1.103)
  -p, --remote-script-path  Path to remote script (default: fio_test/collect_rapl_ipmi_power_fans_speed.sh)
  -e, --fio-experiment    FIO experiment (default: sread_64k_linux)
  -d, --directory         Log directory (default: fio_log)
  -o, --log-output        Log file name (default: <fio_config>.result)
EOF
  exit 1
}

# Default variables
REMOTE_USER="dedongx"
REMOTE_IP="192.168.1.103"
REMOTE_SCRIPT="fio_test/collect_rapl_ipmi_power_fans_speed.sh"
FIO_EXPERIMENT="sread_64k_linux"
FIO_CONFIG="${FIO_EXPERIMENT}.fio"
LOG_DIR="static_scheduler"
LOG_FILE="${LOCAL_FIO_CONFIG}.result"

# Parse command-line arguments
while [[ "$#" -gt 0 ]]; do
  case $1 in
    -u|--remote-user)
      REMOTE_USER="$2"
      shift 2
      ;;
    -ip|--remote-ip)
      REMOTE_IP="$2"
      shift 2
      ;;
    -p|--remote-script-path)
      REMOTE_SCRIPT="$2"
      shift 2
      ;;
    -e|--fio-experiment)
      FIO_EXPERIMENT="$2"
      FIO_CONFIG="${FIO_EXPERIMENT}.fio"
      LOG_FILE="${FIO_CONFIG}.result"  # Automatically update log file name based on config
      shift 2
      ;;
    -d|--directory)
      LOG_DIR="$2"
      shift 2
      ;;
    -o|--log-output)
      LOG_FILE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "Unknown parameter: $1"
      usage
      ;;
  esac
done

# Create log directory if it doesn't exist
mkdir -p "$LOG_DIR"

# SSH to the remote machine and start the collect_rapl_ipmi_power_fans_speed.sh script in the background
#       Notice: collect_rapl_ipmi_power_fans_speed.sh must finish itself!
echo "Starting $REMOTE_SCRIPT on $REMOTE_IP..."
# PID=$(ssh -i /home/dedongx/.ssh/id_ed25519 "${REMOTE_USER}@${REMOTE_IP}" "sudo ./$REMOTE_SCRIPT -t 660 -d fio_test/${LOG_DIR} -e ${FIO_EXPERIMENT}> /dev/null 2>&1 & echo \$!")
# PID=$(ssh -i /home/dedongx/.ssh/id_ed25519 "${REMOTE_USER}@${REMOTE_IP}" "sudo ./$REMOTE_SCRIPT -t 190 -d fio_test/${LOG_DIR} -e ${FIO_EXPERIMENT}> /dev/null 2>&1 & echo \$!")
PID=$(ssh -i /home/dedongx/.ssh/id_ed25519 "${REMOTE_USER}@${REMOTE_IP}" "sudo ./$REMOTE_SCRIPT -t 75 -d fio_test/${LOG_DIR} -e ${FIO_EXPERIMENT}> /dev/null 2>&1 & echo \$!")
echo "$REMOTE_SCRIPT started on $REMOTE_IP with PID: $PID"

# Run fio with the specified configuration file and redirect output to the log file
echo "Running fio locally with config: $FIO_CONFIG..."
fio --write_bw_log=${LOG_DIR}/${FIO_EXPERIMENT} "$FIO_CONFIG" > "${LOG_DIR}/${LOG_FILE}"
# fio --write_bw_log=${LOG_DIR}/${FIO_EXPERIMENT} rread_4k_linux_nvmf_1_disk.fio > "${LOG_DIR}/${LOG_FILE}"
echo "fio execution completed. Results saved to ${LOG_DIR}/${LOG_FILE}"
