# Server Memory Configuration

The default Compose budget is `256m` with a `128m` reservation. Go receives
`GOMEMLIMIT=192MiB`, leaving headroom for goroutine stacks, HTTP buffers, the
runtime, and the container's non-heap memory.

Override these values in the deployment environment only as a matched set:

```dotenv
SERVER_MEMORY_LIMIT=256m
SERVER_MEMORY_RESERVATION=128m
GOMEMLIMIT=192MiB
GOGC=100
```

Keep `GOMEMLIMIT` below `SERVER_MEMORY_LIMIT`; use roughly 75–85% for this
service. Raise the container limit before raising `GOMEMLIMIT` when a larger
library or more concurrent media requests require it. `GOGC=100` is the normal
GC pacing target and should not be reduced solely to mask a memory leak.
