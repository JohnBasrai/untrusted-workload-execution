
## What lives on the Control / Coordination Plane (DDS)

### Categories of control-plane messages

#### 1️⃣ Worker state & liveness

Examples:

* `WorkerAvailable`
* `WorkerBusy`
* `WorkerUnhealthy`
* `WorkerDraining`

Why DDS fits:

* Many readers
* Low latency
* No broker bottleneck
* Late joiners get current state

---

#### 2️⃣ Resource and capacity advertisements

Examples:

* CPU availability
* Memory pressure
* NUMA locality
* cgroup headroom

This lets the master scheduler:

* Make placement decisions
* Avoid overloaded NUMA nodes
* React in near-real time

---

#### 3️⃣ Scheduling intent (not execution)

Examples:

* “Prefer shard X”
* “Throttle queue Y”
* “Pause scheduling to node Z”
* “Rebalance load”

Important distinction:

> These messages **influence scheduling**, they don’t *do* work.

---

#### 4️⃣ Job lifecycle signals (high-level)

Examples:

* Job started
* Job completed
* Job failed (summary only)
* Retry requested

The *job itself* lives in the data queue.
The *fact that something happened* lives here.

---

#### 5️⃣ Configuration and control updates

Examples:

* Update concurrency limits
* Change priority weights
* Enable maintenance mode
* Rolling drain commands

DDS work well here because:

* State is authoritative
* New participants converge quickly
* No polling loops

---

## Why DDS is a good fit for this plane

Can be summarized with one sentence:

> “The control plane is state-driven and latency-sensitive, which is why a decentralized pub/sub system like DDS fits better than a brokered queue.”

---

## Avoids the Master Scheduler bottleneck

* Workers publish state locally
* Per-NUMA collectors aggregate
* Master scheduler **subscribes**, not blocks
* No synchronous fan-in

The master becomes:

> a consumer of state, not a serialization point.

---

## How control plane contrasts with the Job / Data Queue

| Control Plane (DDS) | Data Plane (Kafka / AMQP / Redis) |
| ------------------- | --------------------------------- |
| Small messages      | Large payloads                    |
| State & intent      | Work items                        |
| Low latency         | High throughput                   |
| Decentralized       | Brokered                          |
| Soft ordering       | Strong durability                 |
