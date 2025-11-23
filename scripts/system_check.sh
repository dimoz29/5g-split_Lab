#!/bin/bash
# System Check Script for WSL2 Kubernetes Lab

echo "==============================="
echo "      SYSTEM CHECK REPORT      "
echo "==============================="

echo -e "\n[USER INFO]"
whoami
id
groups

echo -e "\n[DISK SPACE]"
df -h

echo -e "\n[MEMORY]"
free -h

echo -e "\n[CPU LOAD]"
uptime

echo -e "\n[TOP PROCESSES - CPU]"
ps aux --sort=-%cpu | head

echo -e "\n[TOP PROCESSES - MEMORY]"
ps aux --sort=-%mem | head

echo -e "\n[NETWORK CONFIG]"
ip a
echo -e "\n[DNS]"
cat /etc/resolv.conf

echo -e "\n[DOCKER INFO]"
docker version
docker info | grep -E "Server Version|Storage Driver|Logging Driver|Cgroup"

echo -e "\n[DOCKER DISK USAGE]"
docker system df

echo -e "\n[CHECK: HELLO WORLD TEST]"
docker run --rm hello-world

echo -e "\n[FINISHED]"
