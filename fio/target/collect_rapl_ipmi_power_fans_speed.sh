#!/usr/bin/bash

# Function to display the usage of the script
usage() {
  cat <<EOF
Usage: $0 [-t <exptime>] [-p <raplperiod>] [-d <directory>] [-e <experiment>]
  -t, --time        Set the experiment time in seconds (default: 210)
  -p, --raplperiod  Set retrival period of RAPL readings in milliseconds (default: 1000)
  -d, --directory   Output file directory (default: /home/dedongx/fio_test/results)
  -e, --experiment  Experiment name (default: system_cpu_power)
EOF
}

# Initialize default values
exptime=210
directory="/home/dedongx/fio_test/results"
experiment="system_cpu_power"
raplperiod=1000

# Parse options
while [[ "$#" -gt 0 ]]; do
  case $1 in
    -t|--time)
      exptime="$2"
      shift 2
      ;;
    -p|--raplperiod)
      raplperiod="$2"
      shift 2
      ;;
    -d|--directory)
      directory="$2"
      shift 2
      ;;
    -e|--experiment)
      experiment="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      usage
      exit 1
      ;;
  esac
done

# Check if output directory exists, if not create it
if [ ! -d "$directory" ]; then
  echo "Warning: Output directory '$directory' does not exist. Creating it now..."
  mkdir -p "$directory"
  if [ $? -ne 0 ]; then
    echo "Error: Failed to create directory '$directory'. Exiting."
    exit 1
  fi
fi

# Create the outfile name based on directory, experiment name, and timestamp
outfile="$directory/$(date +%s)_$experiment"

# Print the chosen configuration
echo "Experiment time: $exptime seconds"
echo "Output directory: $directory"
echo "Experiment name: $experiment"
echo "Outfile: $outfile"

# Begin the experiment
echo "start time: "
echo "$(date +%s)"
echo "==============="

# Start power monitoring
while true; do 
  ipmitool dcmi power reading | grep -e Instant -e timestamp >> "$outfile.power"
  sleep 1
done &
ipmi_pid=$!

# Start fans monitoring
while true; do 
  echo "$(date +%s)" >> "$outfile.fans"
  ipmitool sensor | grep -e FAN >> "$outfile.fans"
  sleep 1
done &
fans_pid=$!

# Start RAPL power monitoring
echo "$(date +%s)" > "$outfile.raplpower.starttime"
perf stat -e power/energy-ram/,power/energy-pkg/ -a -I $raplperiod -o "$outfile.raplpower" sleep "$exptime" &
rapl_pid=$!

# Output process information
echo "Power pids: $ipmi_pid, $rapl_pid, $fans_pid"

# Wait for the experiment time to complete
sleep "$exptime"

# Kill the background processes after the experiment time ends
kill -9 "$ipmi_pid"
kill -9 "$rapl_pid"
kill -9 "$fans_pid"

# Set permissions for the output files
chmod 777 "$outfile.power"
chmod 777 "$outfile.fans"
chmod 777 "$outfile.raplpower"
