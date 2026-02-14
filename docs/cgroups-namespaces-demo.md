# Linux Cgroups & Namespace Demo

## Overview

This repository contains a **hands-on Linux cgroups v2 demonstration** designed to show practical, interview‑ready understanding of:

* CPU, memory, and I/O isolation
* Process hierarchies and cleanup behavior
* How resource limits behave under real load
* Why cgroups matter even on modern systems (SSD, NVMe, containers)

The demo intentionally uses **simple, observable workloads** (`yes`, `sleep`, `ps`) so that kernel behavior is easy to reason about and explain.

This is not a framework — it is a **diagnostic sandbox**.

---

## Connection to System Design

This demo implements the **Worker Execution Environment** layer from my [distributed sandbox orchestration design](https://github.com/JohnBasrai/untrusted-workload-execution/blob/main/system-design.md#24-worker-execution-environment):

| System Design Component | Demo Implementation |
|------------------------|-------------------|
| Linux namespaces (PID, mount, UTS, IPC, net) | [cgroup-worker-config.sh](https://github.com/JohnBasrai/untrusted-workload-execution/blob/main/scripts/cgroup-worker-config.sh) |
| cgroup v2 resource limits (CPU, memory, I/O) | [namespace-isolation.sh](https://github.com/JohnBasrai/untrusted-workload-execution/blob/main/scripts/namespace-isolation.sh)   |
| Worker process isolation | Inline workload (`yes > /dev/null`) |

**Key Design Principle:** Isolation is enforced by the kernel, not cooperative runtime behavior.

---

## Related Material

- [Main System Design](https://github.com/JohnBasrai/untrusted-workload-execution/blob/main/system-design.md) - Complete distributed orchestration architecture

---

## What This Demo Shows

* Creating and configuring cgroups (v2)
* Assigning processes to cgroups
* CPU quotas vs. CPU saturation
* Memory limits and swap control
* I/O weight (relative fairness, not caps)
* Process trees, sudo, and cleanup tradeoffs
* Deterministic cleanup on SIGINT and normal exit

---

## Files

### 🚀 [cgroup-worker-config.sh](https://github.com/JohnBasrai/untrusted-workload-execution/blob/main/scripts/cgroup-worker-config.sh)

**Main demo entrypoint.**

Responsibilities:

* Creates a worker‑specific cgroup under `/sys/fs/cgroup/janus_sandbox/`
* Configures:

  * CPU quota
  * Memory limit (swap disabled)
  * I/O weight
* Launches a controlled CPU‑burning workload (`yes` processes)
* Displays a live process tree
* Cleans up deterministically on:

  * `Ctrl‑C` (SIGINT)
  * Normal exit (timeout)

This script is what you run during the demo.

---

### 🚀 [list-cgroups.sh](https://github.com/JohnBasrai/untrusted-workload-execution/blob/main/scripts/list-cgroups.sh)

Utility script to list and inspect the cgroup hierarchy.

Useful for:

* Verifying cgroup creation
* Inspecting effective values
* Showing that `/sys/fs/cgroup` is a **kernel interface**, not a real filesystem

---

### 🚀 [namespace-isolation.sh](https://github.com/JohnBasrai/untrusted-workload-execution/blob/main/scripts/namespace-isolation.sh)

Demonstrates namespace isolation concepts alongside cgroups.

Used to explain:

* Why PID 1 matters in containers
* How namespaces and cgroups are orthogonal but complementary

---

## Requirements

* Linux system with **cgroups v2 enabled**
* `sudo` access
* Tools:

  * `bash`
  * `ps`
  * `pkill`

To verify cgroups v2:

```bash
mount | grep cgroup2
```

---

## Running the Demo

### Basic run

```bash
sudo ./scripts/cgroup-worker-config.sh 1
```

What you will see:

* cgroup configuration summary
* Live process tree (`ps --forest`)
* Several `yes` processes consuming CPU

### Interrupt with Ctrl‑C

```text
Type Control-C to cleanup and exit...
^C
exit!
```

All worker processes are terminated cleanly.

### Timed exit

If not interrupted, the script exits automatically after ~30 seconds and performs the same cleanup.

---

## Cleanup Strategy (Intentional Design Choice)

The demo uses:

```bash
pkill yes
```

Why this is intentional:

* Keeps the demo focused on **cgroups**, not shell job‑control edge cases
* Works reliably under `sudo`
* Avoids process‑group/session pitfalls

In production code, alternatives might include:

* Session leadership (`setsid`)
* Explicit job tracking (`jobs -p`)
* systemd‑managed cgroups

For this demo, clarity > cleverness.

---

## Key Concepts You Can Explain From This Demo

* Why cgroup files always exist (virtual kernel interface)
* CPU quota vs. CPU usage
* Relative I/O weight vs. absolute limits
* Why SSDs still benefit from I/O scheduling
* Why `sudo` complicates process‑group cleanup
* How to reason about process trees with `ps --forest`
* **How these primitives compose into a distributed system** (see [system design](https://github.com/JohnBasrai/untrusted-workload-execution/blob/main/system-design.md))

---

## Suggested Talking Point (30‑second summary)

> "This demo shows how Linux enforces resource isolation using cgroups v2. We configure CPU, memory, and I/O controls, attach real workloads, observe their behavior, and clean up deterministically. The focus is on understanding kernel behavior rather than building abstractions. **This isolation layer is the foundation for the worker execution environment in my distributed sandbox orchestration design.**"

---

## Notes

* This demo intentionally avoids Docker/Kubernetes to show **bare‑metal kernel mechanics**.
* All workloads are safe and reversible.
* No persistent system changes are made.

---

## License

Demo / educational use.
