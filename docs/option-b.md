Option B — Competing Consumers (Alternative) 

 - An alternative design allows shard schedulers to compete directly
   for jobs from a shared queue.

 - While this simplifies topology and reduces the need for a
   centralized placement step, it gives up deterministic placement and
   makes it difficult to enforce global policies such as locality or
   explicit shard targeting.

- For workloads where placement is cheap and retries are acceptable,
  this tradeoff may be reasonable, but it is not a good fit for
  untrusted, GPU-dense execution environments.


