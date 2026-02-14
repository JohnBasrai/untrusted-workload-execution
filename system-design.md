# **Distributed Sandbox Orchestration System Design**

Distributed system design for sandboxed execution of untrusted workloads.

---

## **1. System Overview**

The goal of this design is to build a distributed, sandboxed execution environment for orchestrating performance-optimized compute workflows used by ML research and infrastructure teams. The system must support high throughput and horizontal scale while providing strong, kernel-enforced isolation guarantees across a shared cluster.

From this goal, the system’s core requirements fall into two categories: constraints explicitly implied by the job description and requirements that emerge from distributed systems best practices at scale.

### Requirements Confirmed from Job Description

* Isolation stronger than "best-effort" containers
* GPU-first placement logic
* Highly performant arbitrary code execution

> **Note**: GPU-first means select shards based on GPU availability and
> type before considering CPU/RAM - this prevents GPU underutilization
> and fragmentation.

### Requirements Based on Distributed Systems Best Practices

* Deterministic scheduling decisions
* Explicit admission control
* Fast, visible backpressure
* Failure semantics that are easy to reason about

See [Distributed Systems Best Practices](docs/distributed-systems-best-practices-references.md)

At a high level, the system consists of a **Master Scheduler** coordinating multiple **Shard Schedulers**, each responsible for placing and supervising work on a subset of workers.

```

        [Master Scheduler]
                │
                ├── [Shard 0  → Workers]
                ├── [Shard 1  → Workers]
                ⋮         ⋮
                └── [Shard 31  → Workers]

```
A production version would include tuning parameters for the above.

### **Shard Examples**

Typical shard configurations might include:

* Intel Xeon Scalable systems with ~32 physical cores
* Ampere family systems with 32–128 physical cores

Each shard represents a failure and scheduling boundary.

---

## **2. Core Architecture**

### **2.1 System Diagram**

```

┌──────────────┐   ┌──────────────┐          ┌──────────────┐
│ Researcher-1 │   │ Researcher-2 │   …      │ Researcher-N │
└──────┬───────┘   └──────┬───────┘          └───┬──────────┘
       │                  │                      │
       └──────────────────┴────┬─────────────────┘
                               ↓
                      ┌───────────────────┐ • Regionally located (replicas)
                      │   Ingress Tier    │ • Horizontally scalable
                      │ (AuthN / AuthZ)   │ • Enforces authentication
                      │ Admission Control │ • Enforces backpressure
                      │ Backpressure      │ • Forwards to Job Queue
                      └────────┬──────────┘ • Observes capacity signals (control plane) `O(n)`
                               │            • Subscribes to results channel
                               │
                               ↓
┌───────────────────────────────────────────────────────────────────┐
│                  Control / Coordination Plane                     │
│                            (DDS)                                  │
├───────────────────────────────────────────────────────────────────┤
│                        Job / Data Queue                           │
│                    (Kafka / RabbitMQ / Redis)                     │
└──────────────────────────────┬────────────────────────────────────┘
                               │ Consume Jobs
                               ↓
                    ┌───────────────────────┐
                    │  Master Scheduler     │ • Global placement decisions
                    │ - Framentation Control│ • Shard selection / Policy enforcement
                    │ - Job Assignment      │ • Failover / leadership role
                    │ - Job Placement Policy│ • Read job Q, write to shard Q
                    │ - Health Monitoring   │ • Publish state to DDS
                    └──────────┬────────────┘
                               │ Persist Job State (WAL)
                               ↓
                    ┌──────────────────────┐
                    │  Job Metadata DB     │
                    │    (PostgreSQL)      │
                    │  - Job state         │
                    │  - Sharded by        │
                    │    researcher_id     │
                    └──────────────────────┘
                               │ Send Jobs Assignments to correct shard
                               │
        ┌──────────────────────┼──────────────────────┐
        │                      │                      │
        ↓ Shard 0              ↓ Shard 1   ⋯          ↓ Shard 31
┌──────────────────┐  ┌──────────────────┐   ┌──────────────────┐ • Local scheduling decisions
│ Shard Scheduler  │  │ Shard Scheduler  │   │ Shard Scheduler  │ • Worker pool management
│                  │  │                  │   │                  │ • Capacity reporting to master
│  Worker Pool     │  │  Worker Pool     │   │  Worker Pool     │ • No global policy authority
│  (32 cores)      │  │  (32 cores)      │   │  (32 cores)      │
│                  │  │                  │   │                  │
│ Worker 1         │  │ Worker 1         │   │ Worker 1         │
│  [Job 123]       │  │  [Job 789]       │   │  [Idle]          │ Each Worker:
│  ├─ 4 cores      │  │  ├─ 4 cores      │   │  ├─ 4 cores      │  • Runs untrusted code
│  └─ 8GB RAM      │  │  └─ 8GB RAM      │ ⋯ │  └─ 8GB RAM      │  • Namespace isolation
│                  │  │                  │   │                  │  • cgroup resource limits
│ Worker 2         │  │ Worker 2         │   │ Worker 2         │  • GPU access control
│  [Job 456]       │  │  [Idle]          │   │  [Job 234]       │  • No scheduler logic
│  ├─ 4 cores      │  │  ├─ 4 cores      │   │  ├─ 4 cores      │  • Emits metrics / logs
│  └─ 8GB RAM      │  │  └─ 8GB RAM      │   │  └─ 8GB RAM      │
│                  │  │                  │   │                  │
│  ⋯ (8 workers)   │  │  ⋯ (8 workers)   │   │  ⋯ (8 workers)   │
│                  │  │                  │   │                  │
│ Each worker:     │  │ Each worker:     │   │ Each worker:     │
│ - Namespace      │  │ - Namespace      │   │ - Namespace      │
│   isolation      │  │   isolation      │   │   isolation      │
│ - cgroup limits  │  │ - cgroup limits  │   │ - cgroup limits  │
└────────┬─────────┘  └────────┬─────────┘   └────────┬─────────┘
         │                     │                      │
         └─────────────────────┼──────────────────────┘
                               │
                               │ Status Reports
                               │ (Job completion, failures, resource metrics)
                               │
                               ↓              • Same Master Scheduler (logical component)
                    ┌──────────────────────┐  • Reports are asynchronous
                    │  Master Scheduler    │  • Fire-and-forget
                    │ (Metrics / Status)   │  • Buffered channels
                    └──────────┬───────────┘  • Lock-free queues
                               │              • and Workers never wait on MS.
                               │
                               ↓
                  ┌──────────────────────────────┐ • Job results / status → RabbitMQ
                  │ Metrics / Logs / Job Results │ • Metrics → prometheus
                  │ (Async Event Streams)        │ • Logs → logging pipeline
                  └──────────────────────────────┘

• All communication paths are asynchronous; no worker or scheduler
  ever blocks on the control plane or user-facing APIs.

```

---

### **2.2 Control / Coordination Plane**

The control plane uses two technologies:

**Consensus (etcd or ZooKeeper):**
* Used for leader election only
* Determines which scheduler instance is the active master

**State Distribution (DDS):**
|||
|--------------------------------------|-------------------------------|
|   • Cluster-wide state dissemination | all schedulers mirror master's view |
|   • Scheduler convergence            | non-master schedulers stay synchronized |
|   • Capacity signals                 | ingress tier observes cluster health |
|   • Health and liveness              | rapid failure detection |

**Why this split:**
* etcd/ZooKeeper provides battle-tested consensus (Raft/Zab)
* DDS provides low-latency pub/sub for high-frequency control messages
* All scheduler instances maintain synchronized state via DDS
* On master failure, the new leader has current state and resumes immediately

**Note:**
* All schedulers run the same Rust binary
* Non-master schedulers shadow the master's decisions via DDS
* Failover is fast because state is already replicated
* DDS carries **only** control traffic (small messages, no job payloads)

---

### 2.3 Job / Data Plane

The data plane handles **durable job transport** and retry semantics:

* Job submission is decoupled from execution
* Messages are persisted until acknowledged
* Dead-letter queues capture poison jobs

<details>
<summary><strong>Technology Options (click to expand)</strong></summary>

<br>

**Kafka**
* Distributed commit log with partitions
* Strong durability and replication guarantees
* Built-in partitioning maps naturally to shards
* Can replay jobs from any offset (operational flexibility)
* Requires ZooKeeper/KRaft consensus (additional complexity)

**RabbitMQ**
* Message broker with flexible routing (exchanges, queues, bindings)
* AMQP protocol with delivery acknowledgments
* Dead-letter queues for poison jobs
* Fewer moving parts than Kafka (single broker can run standalone)
* Weaker ordering guarantees than Kafka within a queue

**Redis Streams/Lists**
* In-memory data structure with optional AOF/RDB persistence
* Consumer groups provide competing consumer pattern
* Simpler deployment (single process, no external dependencies)
* Weaker durability than Kafka/RabbitMQ (in-memory primary storage)
* Limited retention (memory-bound, no long-term log storage)

**Selection Criteria:**

* **Durability needs**: Jobs that cannot be lost → Kafka or RabbitMQ
* **Replay requirements**: Need to reprocess old jobs → Kafka
* **Operational complexity**: Minimal ops team → RabbitMQ or Redis
* **Throughput**: Very high sustained load → Kafka
* **Latency**: Sub-millisecond critical → Redis (with durability tradeoff)

</details>

This plane is intentionally separate from DDS to avoid coupling control decisions to job durability.

---

### **2.4 Worker Execution Environment**

Each worker executes untrusted jobs under strict isolation:

* Linux namespaces (PID, mount, UTS, IPC, net)
* cgroups for CPU, memory, I/O, and GPU limits
* Read-only root filesystem
* Network restrictions per job

Isolation is enforced by the kernel, not cooperative runtime behavior.

**Execution Environment Demo scripts**:

- [cgroup-worker-config.sh](https://github.com/JohnBasrai/untrusted-workload-execution//blob/main/scripts/cgroup-worker-config.sh) - shows Linux namespaces (PID, mount, UTS, IPC, net)
- [namespace-isolation.sh](https://github.com/JohnBasrai/untrusted-workload-execution/blob/main/scripts/namespace-isolation.sh)   - shows cgroup v2 resource limits (CPU, memory, I/O)

---

## **3. Ingress & Admission**

### **3.1 Ingress Tier**

Researchers submit jobs via a set of regionally distributed ingress servers. These servers are responsible for:

* Authentication (AuthN)
* Authorization (AuthZ)
* Job validation and normalization
* Metadata assignment (job ID, priority, constraints)

> Per-tenant limits the organization's total resource consumption, while per-project allows finer-grained control within that allocation.

Once validated, jobs are published to a durable message queue, not directly to schedulers.

> ✅ Researcher → Ingress → [Message Queue] → Scheduler
>
> ❌ Researcher → Ingress → Scheduler (no direct path)

---

### **3.2 Backpressure & Admission Control**

Backpressure is enforced by Ingress **before jobs enter the system**.

Mechanisms include:

* Per-tenant and per-project quotas
* Global queue depth thresholds
* GPU availability awareness
* Scheduler health signals via DDS

When limits are exceeded:

* Ingress may reject submissions synchronously
* Or apply rate limiting / delayed acceptance
> **Rate limiting** rejects excess requests immediately (e.g., HTTP 429) to enforce fairness and protect the system.
> **Delayed acceptance** slows admission by holding requests briefly until capacity is available, smoothing bursts without rejection.

Backpressure is **explicit and visible**, not emergent from overloaded workers.

---

## **4. Job Lifecycle & Scheduling**

### **4.1 End-to-End Job Flow**

1. Researcher submits job to ingress
2. Ingress validates and publishes job to data plane
3. Scheduler consumes job metadata
4. Placement decision is made based on capacity and constraints
5. Job is assigned to a shard
6. Worker executes job and reports status

See [End-to-End Job Flow](https://github.com/JohnBasrai/untrusted-workload-execution/blob/main/docs/4.1-end-to-end-job-flow.md)

---

### 4.2 Routing Model

The system supports two routing strategies. This section describes the **recommended approach (Option A)** used for untrusted, GPU-dense workloads.  An alternative pull-based model (Option B) is discussed separately for comparison.

#### Option A — Move Model (Recommended)

Ingress publishes jobs to a global intake queue.  
The master scheduler reads messages **without acknowledging**, selects a target shard, and writes the job to the shard-specific queue.  
Only after the write succeeds does the master ACK the intake message.

**Properties**

- Exactly-once delivery at the shard boundary
- Failover-safe (unacked intake messages reappear)
- Clear ownership of placement decisions

See **[4.2 Routing Model — Option B (Pull Model)](docs/4.2-routing-model.md)**  for the alternative design and tradeoffs.

### **4.3 Result Delivery Pattern**

**Challenge:** A single results queue becomes a serialization bottleneck at scale.

**Solution:** Each ingress instance subscribes to a dedicated result topic, enabling direct result routing without central queue contention.

---

#### Implementation (Kafka)

Each ingress instance maintains:
1. Dedicated result topic: `results_ingress_{instance_id}`
2. HashMap of pending RPCs: `correlation_id → response_channel`

**Job message format:**

```json
{
  "job_id": "550e8400-e29b-41d4-a716-446655440000",
  "correlation_id": "550e8400-e29b-41d4-a716-446655440000",
  "callback_address": "kafka://results_ingress_7",
  "researcher_id": "user_alice",
  "requirements": {
    "model": "janus-large",
    "context_id": "alice_quantum_research",
    "gpu_type": "A100",
    "gpu_count": 2
  },
  "payload_uri": "s3://janus-jobs/alice/job_550e8400.tar.gz"
}
```

**Ingress workflow:**

```rust
// 1. Generate correlation_id and create pending RPC context
let correlation_id = Uuid::new_v4();
let (tx, rx) = oneshot::channel();
pending_rpcs.insert(correlation_id, tx);

// 2. Publish job with callback_address
let job = JobMessage {
    job_id,
    correlation_id,
    callback_address: format!("kafka://results_ingress_{}", instance_id),
    ...
};
kafka_producer.send(job);

// 3. Await result on response channel
let result = rx.await?;
```

**Worker workflow:**

```rust
// 1. Execute job
let result = execute_job(&job).await?;

// 2. Publish result to callback_address with correlation_id
let response = JobResult {
    correlation_id: job.correlation_id,  // Echo back for matching
    job_id: job.job_id,
    status: "completed",
    result_uri: "s3://janus-results/...",
};
kafka_producer.send_to(job.callback_address, response);
```

**Result matching:**

```rust
// Ingress consumes from its dedicated result topic
for result in kafka_consumer.iter() {
    if let Some(tx) = pending_rpcs.remove(&result.correlation_id) {
        tx.send(result);  // Complete the async RPC
    }
}
```

---

#### Benefits

* **No central bottleneck** - each ingress has its own result channel
* **Natural load distribution** - results route directly to originating ingress
* **Horizontal scaling** - add ingress instance, add result topic
* **Ingress remains stateless** - pending RPC context is in-memory only

---

#### Scaling Considerations

**Typical deployment:** 10-100 ingress instances → 10-100 result topics (well within Kafka's limits)

**Large deployment:** For 1000+ ingress instances, **Kafka's partition-based routing** can be used as an alternative (single `results` topic with `ingress_instance_id` as partition key). Core principle remains: no central results queue.

**References:**
* [Kafka Partition: All You Need to Know & Best Practices](https://github.com/AutoMQ/automq/wiki/Kafka-Partition:-All-You-Need-to-Know-&-Best-Practices).
* [RabbitMQ vs Kafka: Head-to-head confrontation in 8 major dimensions](https://medium.com/@hubian/rabbitmq-vs-kafka-head-to-head-confrontation-in-8-major-dimensions-7de8a3193dfd)

---

#### Production Precedent

I've used this pattern successfully in production environments at Voyager Defense & Space, routing async commands between ground stations and airborne sensor payloads:

* Ground stations initiated async commands to airborne sensors
* Sensor gateway routed replies back to the correct originating ground workstation
* Used correlation IDs to match requests with responses
* Pattern worked reliably across air-to-ground satellite links

Same principle applies here with ingress instances instead of ground stations.

---

## **5. Failure Handling**

### **5.1 Failure Scenarios**

The system is designed to handle:

* Master scheduler crash
* Shard scheduler crash
* Worker crash during execution
* Network partitions

etcd/ZooKeeper ensure rapid detection of scheduler failures and re-election of leadership.

---

### **5.2 Idempotency & Duplicate Mitigation**

Because failures can occur between read and write operations:

* Jobs carry stable, unique IDs
* Shard queues reject duplicate job IDs
* Execution is idempotent at the worker boundary

Duplicate scheduling is detectable and safe.

---

## **6. State & Metadata**

### **6.1 Job Metadata Store**

A lightweight metadata store tracks:

* Job state transitions
* Retry counts
* Placement history

This store acts as a **write-ahead log**, not a source of truth for execution.
Logs the *intent* to do something **before** doing it, so we can replay if we have a crash.

See [6.1 Job Metadata Store.md](docs/6.1-job-metadata-store.md)

---

### **6.2 Shard Queues**

Each shard owns its queue(s), which:

* Define the shard’s workload
* Provide isolation between shards
* Enable independent scaling and draining

---

## **7. GPU-Aware Scheduling**

Scheduling decisions account for:

* GPU type and count
* Memory availability
* NUMA locality - (Prefer keeping GPU + CPU memory local to avoid cross-socket traffic)
* Existing GPU fragmentation

Placement aims to minimize interference and maximize throughput.

---

## **8. Observability**

Workers emit **raw metrics** to a dedicated metrics pipeline (e.g., Prometheus / OTLP).

Schedulers consume **aggregated summaries only**, avoiding control-plane overload.

DDS is *not* used for metrics transport.

---

## **9. Scalability & Throughput**

The architecture scales along three axes:

* More ingress servers → higher submission rate
* More shards → higher scheduling parallelism
* More workers per shard → higher execution throughput

### Scaling Ingress Capacity Signals

In the current design, ingress subscribes directly to all shard heartbeats. This works at small scale (32 shards) but creates O(N) message fan-in at larger scale (1024+ shards).

**Options to address scaling:**
 1. Hierarchical Aggregation - O(log N) messages
 2. Sampled Gossip Protocol  - O(1) messages to ingress

**Recommended approach:** Hierarchical aggregation where regional aggregators publish detailed shard-level capacity (~32 shards per region). Each regional message contains individual shard capacity data (1-2KB), allowing ingress to maintain full cluster visibility while receiving only ~32 messages per heartbeat interval.

Ingress answers: *Is the global cluster above 80% capacity?* If yes, apply backpressure globally. Master scheduler handles intelligent placement (data locality, GPU types, transfer times).

See [Capacity Signal Aggregation Strategies](docs/capacity-signal-aggregation-strategies.md) for details.

---

## **10. Comparison to Kubernetes**

This architecture can be built on Kubernetes, or even complement it in hybrid setups, but with some tradeoffs for our specific needs:

* Scheduling is indirect and eventually consistent
* Admission control requires heavy customization
* GPU placement is harder to make deterministic
* Control-plane latency is higher

Kubernetes provides excellent elasticity and broad ecosystem support. This design simply prioritizes **determinism**, **isolation**, and **debuggability** for untrusted GPU tasks

For certain problem classes, that tradeoff matters.

For on this topic see [Kubernetes vs This Design](https://github.com/JohnBasrai/untrusted-workload-execution/blob/main/docs/kubernetes-vs-this-design.md)

---
