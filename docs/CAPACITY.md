# How many attendees the hub takes

Measured, not estimated. `scripts/loadtest-mcp.py` fires N concurrent MCP
clients that each do a full handshake and then one tool call, all released
together — the worst case, which is everyone running `make step-04` at once.

## Results

Heavy queries are the aggregates an agent actually writes to answer "has
anything got worse this week" (`sum by (service) (count_over_time(...[7d]))`).
Light queries are the discovery calls it makes while orienting itself.

| Loki node | Clients | Query | Result |
|---|---|---|---|
| 2 core | 25 | heavy | 10.6s |
| 2 core | 50 | heavy | 20.9s |
| 2 core | 100 | heavy | **66 of 100 failed** with Loki 504s |
| **4 core** | 50 | heavy | **12.1s** |
| **4 core** | 100 | heavy | **23.7s, zero failures** |
| 4 core | 100 | light | 2.1s |

**Verdict: 50 attendees is comfortable. 100 works.**

## The bottleneck is Loki's CPU, and only Loki's

Under 50 concurrent heavy queries:

```
loki-0        1207m CPU     ← saturated
grafana          3m
mcp-grafana      2m         ← idle
mcp-proxy        1m         ← idle
```

Latency scaled exactly linearly with client count, which is the signature of a
fixed-capacity bottleneck rather than something that degrades gracefully.

**More nodes do not help.** Loki single-binary is one process; it cannot use
more cores than the node it is on. Two extra medium nodes would have changed
nothing. What fixed it was one *bigger* node: `hub-01` now provisions a
`g4s.kube.large` pool alongside the medium ones, and `hub-02` pins Loki to it
with a nodeSelector on `kubernetes.civo.com/civo-node-size`.

## What did not help

- **Results caching** (`cache_results` with an embedded cache). Enabled anyway
  — it should help real traffic, where everyone asks the same demo questions
  within a few minutes — but it made no difference to the load test, because
  those use *instant* queries, which do not go through the query-range cache.
- **`split_queries_by_interval: 1h`** (down from 672 subqueries per 7-day
  query to 168). Kept, since it reduces obvious waste, but the numbers did not
  move. The work was never in scheduling; it was in scanning.

Worth knowing before optimising further: the fix was hardware, and two
plausible-sounding config changes did nothing.

## If you need more headroom

In order of effect:

1. **A bigger Loki node.** `g4p.kube.small` is 4 core / 16GB. Set
   `LOKI_NODE_SIZE=g4p.kube.small` before `hub-01`.
2. **Shorten the demo window.** A 24h aggregate costs a fraction of a 7d one.
   The seeded incidents are all visible in 48h except the search latency creep.
3. **Stagger the room.** Half start step-04 while the other half are still on
   step-03. Two minutes of offset removes the entire spike.

## Other limits, none of them close

| Thing | Capacity | Set by |
|---|---|---|
| MCP tokens | 60 | `ATTENDEE_COUNT` in `hub-06`, tops up without invalidating issued ones |
| Webhook inbox codes | unique to 99 | word-pair + index suffix in `sink.py` |
| Credential claims | unlimited | wraps and shares if the key pool is short, never blocks |
| Civo clusters | **your account quota** | the real ceiling — default limits bite around 10 |
| relax.ai | unknown | ask the relax team about per-key and account rate limits |

The two that will actually stop you at 50 are both other people's queues: the
Civo cluster quota and relax.ai's rate limits.
