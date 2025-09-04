# Reset settings of remote CPU control mechanisms
#!/usr/bin/bash

# --- Configuration ---
REMOTE_USER="dedongx"
REMOTE_IP="192.168.1.103"
SSH_KEY="/home/dedongx/.ssh/id_ed25519"

# --- Reset CPU settings ---
ssh -i $SSH_KEY $REMOTE_USER@$REMOTE_IP "sudo cpupower frequency-set -g performance"
ssh -i $SSH_KEY $REMOTE_USER@$REMOTE_IP "sudo powercap-set intel-rapl -z 0 -c 1 -l 324000000"
ssh -i $SSH_KEY $REMOTE_USER@$REMOTE_IP "echo '1600000 100000' | sudo tee /sys/fs/cgroup/user/cpu.max"
