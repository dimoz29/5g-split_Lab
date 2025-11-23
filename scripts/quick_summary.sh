#!/bin/bash
# Quick summary script for system_check.sh output
# Usage:
#   ./quick_summary.sh               # runs system_check.sh and summarizes
#   ./quick_summary.sh output.log    # summarizes an existing log file

LOGFILE="$1"

if [ -z "$LOGFILE" ]; then
    LOGFILE="system_check_raw.log"
    echo "[INFO] Running system_check.sh and saving raw output to $LOGFILE ..."
    ./system_check.sh > "$LOGFILE" 2>&1
fi

echo "====================================="
echo "       SYSTEM SUMMARY REPORT"
echo "====================================="

# User
USER_NAME=$(grep -m1 "^\[USER INFO\]" -A2 "$LOGFILE" | sed -n '2p')
echo "User: $USER_NAME"

# Disk
DISK_USE=$(df -h | grep "/$")
echo "Disk usage: $DISK_USE"

# Memory
MEM_TOTAL=$(grep -i "Mem:" "$LOGFILE" | awk '{print $2}')
MEM_USED=$(grep -i "Mem:" "$LOGFILE" | awk '{print $3}')
MEM_FREE=$(grep -i "Mem:" "$LOGFILE" | awk '{print $4}')
echo "Memory: total=$MEM_TOTAL used=$MEM_USED free=$MEM_FREE"

# Docker daemon
DOCKER_VERSION=$(grep -m1 "Version" "$LOGFILE")
if grep -q "Server: Docker" "$LOGFILE"; then
    DOCKER_STATUS="Running"
else
    DOCKER_STATUS="NOT running"
fi
echo "Docker: $DOCKER_STATUS ($DOCKER_VERSION)"

# Container test
if grep -q "Hello from Docker!" "$LOGFILE"; then
    echo "Docker test container: OK"
else
    echo "Docker test container: FAILED"
fi

# Network
if grep -q "inet " "$LOGFILE"; then
    NET_STATUS="Online"
else
    NET_STATUS="Check network"
fi
echo "Network: $NET_STATUS"

echo "====================================="
echo "Summary complete."
