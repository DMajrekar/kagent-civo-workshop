# How many attendees the hub takes

Measured, not estimated. `scripts/loadtest-mcp.py` fires N concurrent MCP
clients that each do a full handshake and then one tool call, all released
together — the worst case, which is the whole room asking an agent its first
question in the same ten seconds after round two unlocks.

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
3. **Stagger the room.** Add the agents one at a time rather than all at
   once. People try each new one as it appears, which spreads the load.

## What changed with the CTF format

These numbers were measured when every attendee ran an agent on their own
cluster. The Loki side is unchanged — it is the same queries arriving at the
same Loki — but three things are new and **none of them has been load-tested**:

| Thing | Why it matters | Check before the day |
|---|---|---|
| **One relax.ai key for the room** | Every agent turn from every player is billed and rate-limited against the hub's single key. Before, each attendee had their own. | Ask relax.ai for the per-key rate limit and compare it with players × about 6 model calls per question. |
| **Agent pods are shared** | One `log-detective` pod now serves everyone. kagent agents handle concurrent sessions, but 50 at once on one pod is not something this repo has measured. | Open the dashboard in several browsers and ask at the same moment. If it queues, raise `spec.declarative.deployment.replicas` in `agents/*.yaml`. |
| **Round one is Grafana on phones** | Fifty people running a 7-day `count_over_time` in Explore is the same heavy query as the table above, arriving in a burst when round one starts. | Covered by the 4-core numbers above, but only up to 100 concurrent. |

`scripts/loadtest-mcp.py` still measures the Loki path. Point it at a
port-forward of `svc/mcp-public`, since the endpoint is no longer public.

## Other limits

| Thing | Capacity | Set by |
|---|---|---|
| Players | no fixed limit | state is one JSON file; handles are unique to 576 before the word pairs repeat (the number suffix keeps them distinct) |
| Guesses | 12 a minute per player | `SUBMIT_PER_MIN` in `ctf.py` |
| Joins | 120 a minute per IP address | `JOIN_PER_MIN` — loose on purpose, because a mobile carrier puts a whole room behind a few addresses |
| relax.ai | unknown | ask the relax team — see above |
