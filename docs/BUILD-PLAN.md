# Build plan — 15 days to 2026-09-26

Ordered by risk, not by how the workshop reads. The two things that can kill
this are both at the top and both resolvable this week.

## Day 1 — de-risk (blocking, do before writing anything else)

- [ ] **Probe relax.ai tool calling.** `scripts/probe-relax.sh` — a raw
      `chat/completions` call with a `tools` array, asserting the model emits a
      well-formed `tool_calls` response, then a second turn feeding the result
      back. Test every candidate model; pick on tool-call reliability, not on
      benchmark scores. **If no model does tool calls reliably, the workshop
      design changes and we need to know now, not on day 12.**
- [ ] Confirm the shared relax.ai key's rate limit and quota. 25 people ×
      an agent loop is a lot of requests in a 15-minute window. Ask relax.ai to
      raise it if needed — that is a lead-time item.
- [ ] Confirm Civo account quota allows N simultaneous clusters in one region.
      Default account limits will bite at ~10. **Lead-time item — raise a
      support ticket today if it needs lifting.**

## Days 2–4 — the hub

- [ ] `hub-01` Civo cluster, firewall, DNS record for the MCP endpoint
- [ ] `hub-02` Loki (single binary, persistent volume) + Alloy
      — `limits_config` tuned: `reject_old_samples: false` for backfill,
        `max_query_length`, `max_entries_limit_per_query` to survive 25 agents
- [ ] `hub-03` Grafana + Loki datasource (also your own debugging window)
- [ ] `hub-04` the misbehaving-app fleet (see INCIDENTS.md)
- [ ] `hub-05` backfill job — writes 7 days of history with past timestamps
- [ ] `hub-06` mcp-grafana + bearer-auth proxy + cert-manager/TLS
- [ ] `hub-07` webhook sink + wall view (see WEBHOOK-SINK.md)

Get the hub up by **day 4** so it accumulates 11 days of genuine live logs on
top of the backfill. Backfill is the guarantee; live traffic is the garnish.

## Days 5–8 — the attendee path

- [ ] step-01 … step-06 scripts, each idempotent and re-runnable
- [ ] `make rehearse` (DEMO_AUTO=1) green end to end against a throwaway cluster
- [ ] Portable log stack: Loki + mcp-grafana + generators, sized for one
      cluster. **Build this once, it does two jobs** — the WiFi fallback for
      step-04, and the take-home in step-06 that frees their cluster from the
      hub. Worth doing properly for that reason.

## Days 9–11 — rehearsal

- [ ] Full 60-minute timed run, on a clean laptop, start to finish. Time each
      step and compare against RUNSHEET.md. Cut what overruns.
- [ ] Second run with a deliberately broken laptop (no helm, stale kubectl) to
      confirm `make doctor` catches it with a usable message.
- [ ] Load test: 25 concurrent agents hitting the MCP endpoint. This is the
      most likely live failure and the cheapest to prevent.
- [ ] Load test the webhook sink too, and confirm the wall view renders a
      hostile payload (`<img src=x onerror=alert(1)>`) as inert text.

## Days 12–13 — attendee comms

- [ ] Pre-work email with repo link + the "reply if doctor fails" line
- [ ] Decide and publish the hub's shutdown date — attendees keep their
      clusters, so they need to know when the shared MCP endpoint stops
      answering. Put the date in docs/AFTER.md and say it in the room.
- [ ] Workshop cards: cluster naming convention, MCP endpoint, MCP token,
      relax.ai key
- [ ] Record the 3-minute step-04 walkthrough as WiFi insurance

## Day 14 — freeze

- [ ] No changes to the repo after this point except typo fixes
- [ ] Re-seed the hub dataset so "last 24h" is fresh on the day
- [ ] Create 3 hot-spare clusters
- [ ] Verify both relax.ai keys work

## Day 15 — event

- [ ] Morning: `make hub-05` re-seed, smoke-test the MCP endpoint end to end
- [ ] After: rotate the MCP token, `make hub-99` teardown or leave up if you
      promised attendees continued access (decide, and tell them which)
