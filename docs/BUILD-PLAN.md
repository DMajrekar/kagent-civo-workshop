# Build plan — event is Tuesday 22 September 2026

Today is Friday 11 September. That's eleven calendar days but only **six
working days**: Mon 14 – Fri 18, and Mon 21. Plan against the six.

Ordered by risk, not by how the workshop reads.

## Friday 11 Sep — de-risk (today)

- [x] **relax.ai tool calling verified.** `scripts/probe-relax.py` — all four
      chat models pass all four checks (emits well-formed `tool_calls`,
      completes the tool-result loop, handles multiple tools, and doesn't call
      tools when it shouldn't). The workshop design is sound; no redesign
      needed. See "Model choice" below.
- [ ] **Send the relax.ai key request today.** This is the longest external
      dependency and it's the last working day before the weekend — not sending
      it today costs two days of a six-day budget. Agree: headcount + 20% for
      spares and no-shows, quota per key, whether keys persist after the event,
      and delivery format. **Needed by Thursday 17 Sep** to make cards on the
      Friday.
- [ ] **Civo cluster quota.** Confirmed sufficient for the hub plus testing.
      Still needs raising before the event: ~25 attendee clusters plus three
      hot spares in LON1, and default limits bite around 10. Lead-time item.

## Weekend 12–13 Sep — optional but high value

Standing the hub up now costs an hour and buys nine days of genuinely live
logs behind the backfill. If you have the hour, do `hub-01` … `hub-05`.

## Mon 14 – Tue 15 Sep — the hub

- [x] `hub-01` Civo cluster, firewall, DNS record for the MCP endpoint
- [x] `hub-02` Loki (single binary, persistent volume) + Alloy
      — `limits_config` tuned: `reject_old_samples: false` for backfill,
        `max_query_length`, `max_entries_limit_per_query` to survive 25 agents
      — `retention_period` and a PVC sized for seven seeded days plus five
        weeks of live generation (the hub runs until 22 Oct)
- [x] `hub-03` Grafana + Loki datasource (also your own debugging window)
- [x] `hub-04` the misbehaving-app fleet (see INCIDENTS.md)
- [x] `hub-05` backfill job — writes 7 days of history with past timestamps
- [x] `hub-06` mcp-grafana + bearer-auth proxy + cert-manager/TLS
      — **per-attendee MCP tokens**, not one shared token. You're already
        printing a per-person relax.ai key on the card, so a second string
        costs nothing — and it's the difference between revoking one abusive
        token and breaking the endpoint for everyone for three more weeks.
- [x] `hub-07` webhook sink + wall view (see WEBHOOK-SINK.md)

Backfill is the guarantee; live traffic is the garnish. Because backfill
covers the full seven days, a late hub is survivable — but a hub that isn't up
by Tuesday leaves no time to notice it's mis-tuned.

**The hub runs until Thursday 22 October** — a month past the event. Three
consequences for how you build it:

- **The log generators must keep running the whole month.** Attendees' CronJobs
  report on "errors in the past 24 hours". If the generators stop the week
  after the event, everyone's daily report quietly goes empty and the takeaway
  rots without anyone understanding why.
- **It's a public endpoint running unattended for a month.** Rate limits and
  query caps stop being a workshop-day concern and become a standing one.
- **It bills to you for the month.** Set a budget alert.

## Wed 16 – Thu 17 Sep — the attendee path

- [x] step-01 … step-05 scripts, each idempotent and re-runnable
- [x] **Model bake-off** — DeepSeek-V4-Pro. See docs/DEMO-PROMPTS.md.
- [x] Portable log stack: Loki + mcp-grafana + generators, sized for one
      cluster. **Build this once, it does two jobs** — the WiFi fallback for
      step-04, and the take-home in step-06 that frees their cluster from the
      hub.
- [ ] **Thu 17: relax.ai keys must be in hand.** If they've not arrived,
      escalate Thursday morning, not Friday afternoon.

## Still open before the rehearsal

- [x] **TLS on both public endpoints** — `hub-08`. ingress-nginx plus
      cert-manager with real Let's Encrypt certificates. Hostnames default to
      sslip.io so no DNS setup is needed; set `HUB_DOMAIN` to use your own
      domain, which reads better on a card. Also retires the two bare
      LoadBalancers, taking the hub from three to one.
- [x] Cert-expiry incident (#5) — resolved. Signal raised, and the prompt that
      reaches it is in docs/DEMO-PROMPTS.md.
- [x] Timed each step — `make rehearse`, numbers in RUNSHEET.md.

## Fri 18 Sep — rehearsal

- [x] `make rehearse` green end to end from a deleted cluster (13m51s)
- [ ] Full **60-minute timed run** on a clean laptop. Time each step against
      RUNSHEET.md and cut whatever overruns.
- [ ] Second run on a deliberately broken laptop (no helm, stale kubectl) to
      confirm `make doctor` catches it with a usable message
- [ ] Load test: 25 concurrent agents against the MCP endpoint. Most likely
      live failure, cheapest to prevent. Note answers take 30-80s each, so the
      concurrency window is wider than it looks.
- [ ] Confirm the wall view renders a hostile payload
      (`<img src=x onerror=alert(1)>`) as inert text
- [ ] Workshop cards: cluster naming convention, their relax.ai key, their MCP
      token, and the hub shutdown date (**22 Oct 2026**)
- [ ] Pre-work email with the repo link and the "reply if `make doctor` fails"
      line. Sending Friday gives people the weekend — better than Monday.
- [ ] Record the 3-minute step-04 walkthrough as WiFi insurance

## Weekend 19–20 Sep — buffer

Deliberately empty. Something above will have slipped.

## Mon 21 Sep — freeze

- [ ] No repo changes after today except typo fixes
- [ ] Re-seed the hub dataset so "last 24h" is fresh on the day
- [ ] Create 3 hot-spare clusters
- [ ] Verify every relax.ai key and MCP token works
- [ ] End-to-end smoke test: fresh cluster → step-01 → step-05 → report lands
      on the wall

## Tue 22 Sep — event

- [ ] Morning: `make hub-05` re-seed, smoke-test the MCP endpoint
- [ ] After: **leave the hub up until 22 Oct.** Don't rotate the MCP tokens —
      attendees are still using them.

## Tue 20 Oct — two days' notice

- [ ] Email attendees that the endpoint goes on the 22nd, pointing at
      docs/AFTER.md. Turns "my agent broke" into "I knew that was coming".

## Thu 22 Oct — teardown

- [ ] `make hub-99`

---

## Model choice

All four relax.ai chat models pass the probe. Differences that matter here:

| Model | Probe | Latency | Parallel tool calls |
|-------|-------|---------|---------------------|
| `Llama-4-Maverick-17B-128E` | 4/4 | fastest (0.5–1.3s) | yes |
| `DeepSeek-V4-Pro` | 4/4 | slowest (0.7–4.3s) | yes |
| `Kimi-K26` | 4/4 | mid (1.2–4.6s) | sequential only |
| `Nemotron-3-Super` | 4/4 | mid (0.8–3.3s) | sequential only |

**Provisional pick: `Llama-4-Maverick-17B-128E`** — fastest by a clear margin
and it parallelises tool calls, which compounds: an agent loop is several
turns, so 1s/turn versus 4s/turn is the difference between six seconds and
twenty of silence on stage, repeatedly.

But the probe fed the model *synthetic* tool results. It proves the mechanics
work; it says nothing about whether a model writes **correct LogQL against the
real schema**, which is what step-04 actually depends on. Re-run the bake-off
Wed 16 – Thu 17 once the hub has real data, scoring on: does it find the
planted incidents in INCIDENTS.md, and how many turns does it take. Pick the
fastest model that reliably finds at least four of the six. If the fast model
finds three and DeepSeek finds six, take the latency hit — step-04 is the
whole workshop.
