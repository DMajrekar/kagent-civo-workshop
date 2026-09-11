# Run sheet — 60 minutes

Event: **2026-09-26**. Format: live screenshare, attendees follow along on their
own laptops against their own Civo clusters.

Sixty minutes is tight for eight things going wrong at once. The plan below
assumes **pre-work is genuinely done**. If it isn't, you lose the first twenty
minutes to installing `kubectl` and the workshop does not finish.

## Pre-work (sent 3 days ahead, ~10 min for the attendee)

Email the repo link with exactly three instructions:

1. `git clone … && cd kagent-workshop`
2. `cp .env.example .env` and paste in the Civo key from their own account
3. `make doctor` — must print all green

Add one line: *"If `make doctor` does not pass, reply to this email — we will
not have time to debug laptops on the day."* That sentence is worth ten minutes
of session time.

## In the room

| Time | Step | What is on screen | Notes |
|------|------|-------------------|-------|
| 00:00 | — | Welcome, what we're building | Diagram: their cluster → MCP → your hub |
| 00:03 | `make step-01` | Cluster creating | **Everyone fires this now.** Async — returns immediately. |
| 00:05 | — | Talk: what kagent is, why agents in-cluster | ~6 min of air cover while Civo provisions |
| 00:11 | `make step-02` | kagent install + relax.ai ModelConfig | Blocks on cluster ready; stragglers catch up here |
| 00:18 | `make step-03` | First agent + dashboard port-forward | First visual payoff. They ask it a question about their own cluster. |
| 00:27 | `make step-04` | Connect the MCP hub, query 7 days of logs | **The wow.** Guided prompts against seeded incidents. |
| 00:40 | `make step-05` | Daily error-report CronJob | Trigger it manually so they see output immediately |
| 00:50 | `make step-06` | Cut the cord: own key, own Loki | They leave with a cluster that still works tomorrow |
| 00:56 | — | Q&A + what it costs | Point at docs/AFTER.md. Be explicit about billing. |

## Buffer and cut-lines

There is no slack in this. Decide **in advance** what you drop:

- **First cut:** step-06's log stack becomes "read docs/AFTER.md at home", but
  **still swap the relax.ai key live** (30 seconds) — otherwise everyone walks
  out with a cluster that 401s by dinner.
- **Second cut:** step-05 shows a pre-created CronJob's output rather than
  having them apply it (saves 6 min).
- **Never cut:** step-04. It is the entire point of the workshop.

## The takeaway is a running cluster

Attendees keep their clusters. That is the point — but it means two things must
be said out loud, not left in a README:

1. **It bills to their account.** Say the number. Someone finding an unexpected
   Civo charge next month is the one outcome that turns a good workshop into a
   complaint.
2. **The shared key and the hub endpoint expire.** If they don't run step-06,
   their agent breaks within a day and they'll conclude kagent is flaky rather
   than that the workshop credentials were temporary.

## Failure drills

| If… | Do this |
|-----|---------|
| Someone's cluster fails to create | Spare kubeconfigs — pre-create 3 clusters as hot spares |
| Venue WiFi dies | Nothing saves you. Have the recorded 3-min step-04 walkthrough. |
| The hub MCP endpoint is down | `make step-04 FALLBACK=local` deploys a mini-Loki with the same seeded data into their cluster |
| Shared relax.ai key is exhausted | Second key ready; `kubectl -n kagent create secret … --dry-run \| kubectl apply -f -` and restart |
| An attendee is 2 steps behind | Steps are idempotent and independent — tell them to run the *current* step, not catch up |
