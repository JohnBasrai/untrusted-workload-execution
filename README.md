# Distributed Sandbox Orchestration System Design

## Overview

This repository presents a **system design and execution-environment demonstration** for a distributed sandbox orchestration platform intended for large-scale AI research workloads.

The core problem space is **running untrusted, arbitrary code** at scale while preserving:

- Strong isolation guarantees (kernel-enforced, not cooperative)
- GPU-first scheduling and placement
- Deterministic, debuggable behavior under load
- Clear failure semantics and backpressure

The design is motivated by modern AI research platforms where **GPU availability, long-lived worker state, and strict multi-tenant isolation** dominate architectural decisions.

This is **not** a framework or implementation. It is a design exploration backed by concrete, observable kernel-level demos.

---

## What This Repository Contains

The repository has two distinct but intentionally connected parts:

### 1. System Architecture & Scheduling Design

A full end-to-end architecture for a distributed sandbox orchestration system, including:

- Ingress tier with explicit admission control
- Master / shard scheduler hierarchy
- GPU-aware placement and fragmentation control
- Separation of control plane vs data plane
- Failure handling, idempotency, and replay semantics
- Context-aware scheduling for long-lived GPU workers

The complete design lives here:

➡ **[system-design.md](https://github.com/JohnBasrai/untrusted-workload-execution/blob/main/system-design.md)**

That document is the canonical source for the architecture.

---

### 2. Kernel-Level Execution Environment Demo

A set of shell scripts that **demonstrate the worker execution environment** assumed by the system design.

These scripts show, using real workloads and live observation:

- Linux namespaces (PID, mount, UTS, IPC, net)
- cgroups v2 resource isolation (CPU, memory, I/O)
- Process hierarchy behavior and cleanup
- Why kernel primitives matter even without containers

This demo exists to validate and explain the **worker isolation layer** used in the design — not as production tooling.

The demo is documented here:

➡ **[cgroups-namespaces-demo.md](https://github.com/JohnBasrai/untrusted-workload-execution/blob/main/docs/cgroups-namespaces-demo.md)**

---

## Repository Structure

Top-level files of interest:

- `system-design.md`  \
  Full distributed system design and scheduling architecture

- `cgroups-namespaces-demo.md`  \
  Explanation of the execution-environment demo and how it maps to the design

- `cgroup-worker-config.sh`  \
  Main demo entrypoint configuring cgroups and launching workloads

- `namespace-isolation.sh`  \
  Demonstrates namespace isolation alongside cgroups

- `list-cgroups.sh`  \
  Utility for inspecting the live cgroup hierarchy

- `simulate-work.sh`  \
  Simple workload generator used by the demo

---

## Design Philosophy

A few principles guide everything in this repository:

- **Isolation is enforced by the kernel**, not by cooperative runtimes
- **Schedulers must be easy to reason about under failure**
- **Admission control and backpressure are explicit**, not emergent
- **GPU placement drives scheduling**, CPU and memory are secondary
- **Observability beats abstraction** — real behavior matters

Where possible, the design favors:

- Determinism over maximum utilization
- Debuggability over cleverness
- Clear ownership boundaries over global coordination

---

## What This Is (and Is Not)

**This is:**
- A system design suitable for discussion, review, and extension
- A concrete demonstration of Linux isolation primitives
- A foundation for deeper implementation work

**This is not:**
- A production scheduler
- A container runtime
- A Kubernetes replacement

---

## How to Read This Repo

If you’re new to the repository:

1. Start with **this README** for context
2. Read **`system-design.md`** for the full architecture
3. Review **`cgroups-namespaces-demo.md`** to see how the worker model is grounded in real kernel behavior

The demo scripts are intentionally simple so that their behavior can be explained live without hiding behind tooling.

---

## Status

This repository represents a **design-complete, demo-ready snapshot**.

Future work may involve:
- Generalizing naming and structure
- Extracting reusable components
- Implementing portions of the design in Rust or Go

Those steps are intentionally deferred.
