#!/bin/bash
# List all cgroups under janus_sandbox

find /sys/fs/cgroup/janus_sandbox -type d

# Show which processes are in each cgroup
for cgroup in /sys/fs/cgroup/janus_sandbox/*/; do
    echo "=== $cgroup ==="
    cat "${cgroup}/cgroup.procs" 2>/dev/null || echo "  (no processes)"
done

# Also try: systemd-cgls /sys/fs/cgroup/janus_sandbox
