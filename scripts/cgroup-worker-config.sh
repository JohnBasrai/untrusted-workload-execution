#!/bin/bash
# Worker Sandbox cgroup v2 Configuration

## USAGE EXAMPLE
## Launch worker in sandbox
## sudo ./cgroup-worker-config.sh 1
## exec ./sandbox_worker --job-id 123

set -euo pipefail

# Must run as root
if [ "$EUID" -ne 0 ]; then
    echo "$0: Error: Must run as root (use sudo)"
    exit 1
fi

WORKER_ID="${1:-1}"  # Default to worker 1
CGROUP_ROOT="/sys/fs/cgroup/janus_sandbox"
CGROUP_PATH="${CGROUP_ROOT}/worker_${WORKER_ID}"

# Create parent cgroup if needed
mkdir -p "$CGROUP_ROOT"

# Enable controllers in parent cgroup
echo "+cpu +memory +io" > "${CGROUP_ROOT}/cgroup.subtree_control" 2>/dev/null || true

# Create worker cgroup
mkdir -p "$CGROUP_PATH"

# CPU Limit: 4.0 cores
# Format: quota period (both in microseconds)
# 400000 us / 100000 us = 4.0 cores
# Chosen: 4 cores balances parallelism (ML jobs) with job concurrency (8 workers/server)
echo "400000 100000" > "${CGROUP_PATH}/cpu.max"

# Memory Limit: 8GB
# Calculation: 8 * 1024^3 = 8589934592 bytes
# Chosen: 8GB per 4-core worker = 2GB/core, reasonable for research workloads
MEMORY_LIMIT=$((8 * 1024 * 1024 * 1024))
echo "$MEMORY_LIMIT" > "${CGROUP_PATH}/memory.max"

# Memory swap: Disabled
# Reason: Swapping degrades performance 1000x. Better to OOM kill than swap.
# Also prevents swap-based timing side-channels in multi-tenant systems.
echo "0" > "${CGROUP_PATH}/memory.swap.max"
# OOM in cgroups means the kernel forcibly killed a process because that cgroup
# exceeded its allowed memory, regardless of total system memory

# I/O weight: Default (100)
# Range: 1-10,000, default is 100 (fair share)
# Reason: Start with fair share. Could increase for high-priority researchers
#         or decrease for background jobs. Matters when disk is congested.
echo "100" > "${CGROUP_PATH}/io.weight"
# I/O weight is a relative priority knob that controls how much disk bandwidth a
# cgroup gets when the storage device is busy. A fairness hint only.
# Other possible schedulers:
#   mq-deadline → throughput-oriented
#   kyber       → latency hints
#   BFQ         → fairness + latency (How or does the above pick BFQ??)

# Add current shell to cgroup
# All child processes (including worker) inherit limits
echo $$ > "${CGROUP_PATH}/cgroup.procs"

echo
printf "    %s\n" ┌────────────────────────────────────────────────┐
printf "    │ %-47s │\n" "Worker  ${WORKER_ID} cgroup configured: ✅ "
printf "    │ %-46s │\n" " "
printf "    │ %-45s │\n" "Path   : ${CGROUP_PATH}"
printf "    │ %-46s │\n" "CPU    : 4.0 cores (400ms per 100ms period)"
printf "    │ %-46s │\n" "Memory : 8GB (no swap)"
printf "    │ %-46s │\n" "I/O    : weight 100 (default priority)"
printf "    │ %-46s │\n" " "
printf "    │ %-46s │\n" "To run worker in this cgroup:"
printf "    │ %-46s │\n" "  $ sudo $0 ${WORKER_ID}"
printf "    │ %-46s │\n" "  $ exec /path/to/janus_worker --job-id 123"
printf "    %s\n" └────────────────────────────────────────────────┘
echo

# Run a CPU hog inside the cgroup
sudo bash -c '
  echo $$ > /sys/fs/cgroup/janus_sandbox/worker_1/cgroup.procs
  for i in {1..6}; do
      yes ${i} > /dev/null &
  done
  sleep 1
  ps -lf --forest
  echo "Type Control-C to cleanup and exit..."
  trap "echo exit!;pkill yes" EXIT
  sleep 15
'

## **cgroups v2 hierarchy:**
##
## /sys/fs/cgroup/        ← Root cgroup
##   └─ janus_sandbox/    ← Parent group for all workers
##       ├─ worker_1/     ← This worker's cgroup
##       ├─ worker_2/     ← Another worker's cgroup
##       └─ worker_3/
