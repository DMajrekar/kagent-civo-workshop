# The seeded dataset

The workshop lives or dies on this file. Random log noise produces no insights,
the agent says "I found some errors", and the room is unimpressed. What you
want is a **fleet with a plot** — a handful of deliberate, discoverable
incidents with known answers, so step-04 has guaranteed payoffs you can
rehearse.

Shape: a fictional e-commerce platform, 8 services, 7 days of history.

## Baseline hum

All services emit structured JSON at a realistic mix (~95% info, 4% warn, 1%
error) on a diurnal curve — busy 09:00–22:00 local, quiet overnight, with a
weekend dip. Without this the incidents have nothing to stand out against, and
"find the anomaly" is trivial in an uninteresting way.

## The incidents

| # | Service | Story | Discoverable by | Demo prompt |
|---|---------|-------|-----------------|-------------|
| 1 | `checkout` | 5xx rate steps from 0.5% to 9% at day-3 14:20 and never recovers. A `version=v2.3.1` label appears at exactly that timestamp. | Error rate over time, grouped by version | *"Has anything gotten worse this week?"* |
| 2 | `orders-db-proxy` | Connection-pool exhaustion every night 02:00–02:40. `FATAL: remaining connection slots are reserved`. Correlates with a nightly batch job. | Recurring time-of-day pattern | *"Are there any problems that happen on a schedule?"* |
| 3 | `image-resizer` | OOMKill crashloop starting day 5, worsening. Memory-limit logs before each kill. | Restart/kill events + preceding logs | *"Which service is least healthy right now?"* |
| 4 | `notifications` | Emits 80% of total log volume — debug logging left on in prod. Boring, harmless, expensive. | Volume by service | *"Where is our log spend going?"* |
| 5 | `auth` | TLS cert expiry warnings every startup since day 2. Expires in 9 days. Nobody has noticed. | Warn-level text search | *"Is anything about to break that isn't broken yet?"* |
| 6 | `search` | p99 latency creeping up ~8%/day. No errors at all. | Latency in log fields over time | *"Anything degrading slowly?"* |

Six is the right number: enough that two agents asking different questions find
different things, few enough that you can hold all the answers in your head
while presenting.

## Why these six

They cover deliberately different **detection modes**, so attendees learn that
the agent is doing more than grep:

- #1 is a **step change** correlated with a deploy label
- #2 is **periodicity** — invisible unless you aggregate by time-of-day
- #3 is an **escalating trend** plus Kubernetes events
- #4 is about **volume**, not errors — nothing is failing
- #5 is a **prediction**, not a detection — the failure hasn't happened yet
- #6 has **no errors whatsoever** — pure metric-in-logs regression

#5 is the best one to end on. "Nothing is broken, but this will break in nine
days" is the moment people understand why an agent beats a dashboard.

## Backfill mechanics

- Generate deterministically from a fixed seed → the dataset is reproducible,
  so a re-seed on the morning of the event tells the same story.
- Push with explicit past timestamps via Loki's push API in batches, ascending
  per stream.
- Loki rejects old samples by default — set `reject_old_samples: false` (or
  `reject_old_samples_max_age: 336h`) in `limits_config`.
- Anchor all timestamps relative to *run time*, not absolute dates, so
  "yesterday" is always yesterday no matter when you re-seed.
- Keep the live generators running too, so the most recent hour is genuinely
  live and `make step-05`'s "errors in the past 24h" report is never empty.
