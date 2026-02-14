# Scaling Ingress Capacity Signals

## Problem Statement

The ingress tier needs cluster capacity information to enforce admission control and backpressure. At small scale (32 shards), ingress can subscribe directly to all shard heartbeats via DDS. At larger scale (1024+ shards), this approach doesn't scale.

## Current Design (32 shards, 1024 cores)

- Ingress tier subscribes directly to all shard heartbeats via DDS
- Each shard publishes: `{shard_id: 3, available_gpus: 2, cpu_util: 45%}`
- Ingress receives ~32 messages per heartbeat interval (e.g., every 5 seconds)
- Ingress maintains in-memory capacity map: `shard_id → capacity_state`
- Message fan-in is `O(N)` where N = shard count

## Scaled Design (1024 shards, ~131k cores)

Direct subscription to all 1024 shards creates problematic `O(N)` message fan-in to ingress - 1024 messages per heartbeat becomes a bottleneck.

## Scaling Strategies

### Option 1: Hierarchical Aggregation (Recommended)

**Architecture:**

`1024 Shards → 32 Regional Aggregators → Ingress Tier`

**Regional Aggregator (one per 32 shards):**
Publishes **detailed shard-level capacity**, not just averages:

```rust
{
  "region": "us-west",
  "shards": [
    {"id": 0, "gpus_free": 8, "cpu_util": 20%},
    {"id": 1, "gpus_free": 2, "cpu_util": 85%},
    {"id": 2, "gpus_free": 7, "cpu_util": 30%},
    // ... 29 more shards
  ]
}
```

**Message size:** ~32 shards × ~50 bytes = **1.6 KB per region**

**Properties:**
- `O(log N)` message fan-in: 1024 → 32 → ingress
- Ingress receives ~32 messages (one per region)
- Full shard-level visibility maintained
- Can add intermediate aggregation layers if needed (32 → 8 → 1)
- Ingress builds in-memory `HashMap<ShardId, Capacity>` for `O(1)` lookup

**Admission Logic:**
```rust
fn should_admit(job: &Job) -> bool {
    let available_shards: Vec<_> = capacity_map
        .values()
        .filter(|s| s.gpus_free >= job.gpu_requirement)
        .collect();
    
    // Apply backpressure if <20% of shards have capacity
    (available_shards.len() as f64 / total_shards as f64) > 0.20
}
```

**Global backpressure threshold:**
When cluster is >80% utilized globally, ingress applies backpressure to all researchers worldwide. This prevents overshoot beyond capacity.

**Best for:**
- When full shard-level visibility is required
- When message sizes remain manageable (1-2KB per region)
- When deterministic capacity visibility is needed
- Easier to debug and reason about

---

### Option 2: Sampled Monitoring (Gossip Protocol)

**Architecture:**

- Ingress doesn't listen to ALL shards
- Subscribes to random 5% sample (51 shards out of 1024)
- Gets statistically valid cluster health estimate
- Rotates sample periodically


**Properties:**
- Constant `O(1)` message rate regardless of shard count
- Self-healing (dead shards rotate out naturally)
- Requires statistical confidence in sample representativeness
- Loses fine-grained visibility

**Best for:**
- When eventual consistency is acceptable
- When extreme scalability is required (`10,000+` shards)
- When cluster is homogeneous (all shards roughly equivalent)
- When probabilistic guarantees are sufficient

---

## Key Design Principle

**Admission control doesn't need perfect information - it needs "good enough" information with low latency.**

If the cluster is 80% full vs 82% full, the admission decision is the same. The goal is to detect backpressure thresholds, not maintain perfect real-time accounting.

Ingress answers a simple question: **"Is the global cluster above 80% capacity?"**

If yes → Apply backpressure globally
If no → Accept jobs

**Placement intelligence happens at the Master Scheduler:**
- Data locality (job submitted from India, place on India shard)
- GPU type requirements
- Checkpoint location
- Transfer time minimization

---

## Recommended Approach

Start with **hierarchical aggregation** because:

1. Full shard-level visibility with `O(log N)` scaling
2. Messages remain small (1-2KB per region)
3. Debuggability is important for a small team
4. Straightforward to implement and reason about

**Implementation:**

```rust
// Regional aggregator publishes to "capacity-region-{id}" topic
// Ingress subscribes to all regional topics

struct IngressCapacityView {
    capacity_map: HashMap<ShardId, ShardCapacity>,
    last_update: HashMap<RegionId, Timestamp>,
}

impl IngressCapacityView {
    fn on_regional_update(&mut self, msg: RegionalCapacityUpdate) {
        // Update capacity map with detailed shard data
        for shard in msg.shards {
            self.capacity_map.insert(shard.id, shard.capacity);
        }
        self.last_update.insert(msg.region_id, now());
    }
    
    fn cluster_utilization(&self) -> f64 {
        let total_capacity: u32 = self.capacity_map.values()
            .map(|s| s.total_gpus)
            .sum();
        let used_capacity: u32 = self.capacity_map.values()
            .map(|s| s.total_gpus - s.gpus_free)
            .sum();
        
        used_capacity as f64 / total_capacity as f64
    }
    
    fn should_apply_backpressure(&self) -> bool {
        self.cluster_utilization() > 0.80
    }
}
```

---

## Scaling Beyond `10,000` Shards

If scaling to `10,000+` shards:
- Add additional aggregation layers (1024 → 32 → 1 hierarchy)
- Or switch to sampled monitoring for `O(1)` message load
- Revisit whether per-shard visibility is necessary at that scale
