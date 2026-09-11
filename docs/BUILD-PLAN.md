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
- [ ] **Kick off per-attendee relax.ai keys with the relax team.** This is now
      the longest external dependency in the plan and it is not in your
      control. Agree by day 3: how many keys (headcount + 20% for spares and
      no-shows), what quota each carries, whether they persist after the event,
      and the format you'll receive them in. **Keys must be in hand by day 10**
      to make the workshop cards on day 12.
- [ ] Ask the relax team about per-key rate limits too. Per-attendee keys mean
      one person's runaway loop no longer takes down the room — but 25 agents
      starting step-04 within the same 60 seconds is still a spike at the
      account level.
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
      — **issue per-attendee MCP tokens**, not one shared token. You're already
        printing a per-person relax.ai key on the card, so a second string costs
        nothing — and it's the difference between revoking one abusive token
        and breaking the endpoint for everyone for the remaining three weeks.
- [ ] `hub-07` webhook sink + wall view (see WEBHOOK-SINK.md)

Get the hub up by **day 4** so it accumulates 11 days of genuine live logs on
top of the backfill. Backfill is the guarantee; live traffic is the garnish.

**The hub now runs until 2026-10-26** — a month past the event. That changes
three things about how you build it:

- **The log generators must keep running the whole month.** Attendees' CronJobs
  report on "errors in the past 24 hours". If the generators stop the week
  after the event, everyone's daily report quietly goes empty and the takeaway
  rots without anyone understanding why. Treat generator uptime as the thing
  that matters most post-event.
- **Loki needs a retention policy and a big enough disk.** Seven days of seeded
  data plus five weeks of live generation. Size the PVC for the full run, and
  set `retention_period` so it doesn't simply fill up on day 30.
- **It's a public endpoint running unattended for a month.** Rate limits and
  query caps stop being a workshop-day concern and become a standing one. Set
  a budget alert on the hub cluster too — it bills to you for the whole month.

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
- [ ] Workshop cards carry four things per person: cluster naming convention,
      their relax.ai key, their MCP token, and the hub shutdown date
      (**2026-10-26**). The date is also on a slide and in docs/AFTER.md.
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
- [ ] After: **leave the hub up until 2026-10-26.** Don't rotate the MCP
      tokens — attendees are still using them.
- [ ] Set a calendar reminder for 2026-10-24: warn attendees the endpoint is
      about to go, pointing at `make step-06`. Two days' notice turns "my agent
      broke" into "I knew that was coming".
- [ ] 2026-10-26: `make hub-99` teardown.
