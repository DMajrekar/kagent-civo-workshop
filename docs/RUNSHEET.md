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

- **First cut:** step-06 entirely — it becomes "read docs/AFTER.md at home".
  Safe now: attendees have their own relax.ai keys and the hub stays up until
  **2026-10-26**, so nothing breaks when they walk out. This is your real
  buffer; spend it on step-04 if the room is engaged.
- **Second cut:** step-05 shows a pre-created CronJob's output rather than
  having them apply it (saves 6 min).
- **Never cut:** step-04. It is the entire point of the workshop.

## The takeaway is a running cluster

Attendees keep their clusters, their own relax.ai key, and hub access until
**2026-10-26**. So the takeaway genuinely works — but two things still need
saying out loud, not left in a README:

1. **It bills to their account.** Say the number. Someone finding an unexpected
   Civo charge next month is the one outcome that turns a good workshop into a
   complaint.
2. **The hub goes away on 2026-10-26.** Put the date on the slide and in
   docs/AFTER.md. A month is long enough that they will have forgotten, so the
   date needs to be somewhere they'll find it later — which is why step-06
   exists even though it's now the first thing you cut.

## Failure drills

| If… | Do this |
|-----|---------|
| Someone's cluster fails to create | Spare kubeconfigs — pre-create 3 clusters as hot spares |
| Venue WiFi dies | Nothing saves you. Have the recorded 3-min step-04 walkthrough. |
| The hub MCP endpoint is down | `make step-04 FALLBACK=local` deploys a mini-Loki with the same seeded data into their cluster |
| An attendee's relax.ai key doesn't work | Keys are per-attendee, so this is one person, not the room. Keep 3 spare keys on a card; swapping is one `kubectl create secret --dry-run \| kubectl apply -f -` and a rollout restart. |
| An attendee is 2 steps behind | Steps are idempotent and independent — tell them to run the *current* step, not catch up |
