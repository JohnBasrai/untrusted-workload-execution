#!/bin/bash
# Simulate a worker doing some work

echo "Worker starting..."
echo "My PID: $$"
echo "My cgroup: $(cat /proc/self/cgroup)"

# Simulate CPU work (spawns 10 threads, but cgroup limits to 4 cores)
echo "Doing CPU-intensive work (limited to 4 cores)..."
for i in {1..10}; do
    yes > /dev/null &
done

echo "Press Ctrl+C to stop"
wait
