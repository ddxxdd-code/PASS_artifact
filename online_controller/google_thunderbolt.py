import subprocess
import os
import psutil
import time
import numpy as np
import pandas as pd
import sys
import warnings
import time
import signal
import threading
from datetime import datetime
import random


import statistics
from collections import deque

warnings.filterwarnings(action='ignore', category=UserWarning)

powers = []
metrics = []
power_array = [None] * 5
#period = sys.argv[1]
output_file_name = "../data/training-data.csv"

prev = 0
#num_cores = os.cpu_count()
# num_cores = 1
num_cores = 8
start_time = datetime.now()

# Constants
HARD_MULTIPLIER = 0.01
SOFT_MULTIPLIER = 0.75
# THROTTLE_MIN = 0.01    
# THROTTLE_MIN = 0.3
# THROTTLE_MIN = 1
THROTTLE_MIN = 0.5
THROTTLE_MAX = 100
HIGH_THRESHOLD = 0.98  
LOW_THRESHOLD = 0.96   

def core_throttling(index):
    # Define the path to the cgroup v2
    cgroup_path = '/sys/fs/cgroup/'

    # Create a new cgroup for the application if it doesn't exist
    app_cgroup = os.path.join(cgroup_path, 'user')

    # Calculate the cores to be used
    conf_str = str(int(100000 * num_cores * index / 100)) + " 100000"

    # Set the cpuset.cpus for the application cgroup
    with open(os.path.join(app_cgroup, 'cpu.max'), 'w') as f:
        f.write(conf_str)

def calculate_power():
    """Measure IPMI power and store values in the shared list 'samples'."""
    result = subprocess.run(
        ["ipmitool", "dcmi", "power", "reading"],
        capture_output=True,
        text=True
    )
    for line in result.stdout.splitlines():
        if "Instantaneous" in line:
            ipmi_power = float(line.split()[3])  # Assuming power value is the 4th field
            return ipmi_power

def rumd_control(actual_power, target_power, current_bandwidth, random_unthrottle_timeout):
    # if actual_power > target_power:  # If power exceeds the limit
    if actual_power > target_power * HIGH_THRESHOLD:  # Apply hard multiplier
        current_bandwidth *= HARD_MULTIPLIER
        current_bandwidth = max(current_bandwidth, THROTTLE_MIN)
    elif actual_power > target_power * LOW_THRESHOLD:  # Apply soft multiplier
        current_bandwidth *= SOFT_MULTIPLIER
        current_bandwidth = max(current_bandwidth, THROTTLE_MIN)
    else:
        if random.random() < 0.5:
            current_bandwidth = min(current_bandwidth + 2, THROTTLE_MAX)

    core_throttling(current_bandwidth)
    
    # Return the updated bandwidth
    return current_bandwidth

start_of_run = True

def run_stress_ng():
    try:
        global target_power
        global current_bandwidth
        global prev
        global start_of_run
        if start_of_run:
            current_bandwidth = 100
            start_of_run = False
        
        while True:
            actual_power = float(calculate_power())
            with open('/home/dedongx/power_aware_storage/budget', 'r') as file:
                # Read the first line of the file
                line = file.readline()
                # Convert the line to an integer
                target_power = int(line.strip())

            random_unthrottle_timeout = random.randint(1, 5)

            current_bandwidth = rumd_control(actual_power, target_power, current_bandwidth, random_unthrottle_timeout)

            current_time = datetime.now()

            timestamp = (current_time - start_time).total_seconds()
            print(f"{int(timestamp)} | {current_bandwidth} | {target_power} | 0 | 0 | {actual_power}", flush=True)
            time.sleep(1)


    except Exception as e:
        print(f"An error occurred while running stress-ng: {e}")

def signal_handler(sig, frame):
    if os.path.exists("perf-training.dat"):
        os.remove("perf-training.dat")
    exit(0)

if __name__ == "__main__":
    # Register the signal handler for SIGINT (Ctrl+C) and SIGTERM
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)

    while True:
        stress_thread = threading.Thread(target=run_stress_ng)
        stress_thread.start()
        stress_thread.join()
