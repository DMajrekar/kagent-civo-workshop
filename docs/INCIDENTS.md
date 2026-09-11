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

**Incident 2 has to be loud.** It was originally ~16 errors a night against
~480 baseline lines in the same window — technically present, and the agent
correctly reported finding no scheduled problem. The validator had passed it on
raw count. It is now ~474 errors at 02:00 against 0 in a quiet hour, and the
check asserts it *dominates* rather than merely exists. "Present in the data"
and "discoverable by an agent" are different bars.

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

### The rule that matters

**Never backfill into streams that already contain recent data.** This caught
us three separate ways during the build, and each time the symptom was a bare
`HTTP 400` with a dataset that looked almost right:

1. The live generator was running during the backfill.
2. The live generator was paused, but *after* the Loki wipe — so it wrote "now"
   into the freshly emptied Loki in the gap.
3. A generator Deployment was created with `replicas: 1` and started writing
   before the backfill job ran.

Loki accepts out-of-order writes only within a window derived from
`max_chunk_age` (about an hour by default). A stream holding an entry stamped
"now" will reject anything older than that window, so a 7-day backfill fails
almost entirely. Order is: **stop every writer → wipe → backfill → start
writers.**

A partial backfill is worse than a failed one, because nothing downstream
tells you the dataset has holes. The generator therefore counts rejected
batches and exits non-zero, and `hub-05` fails rather than handing a broken
dataset to the validator.

### Other settings

- Generate deterministically from a fixed seed → the dataset is reproducible,
  so a re-seed on the morning of the event tells the same story.
- Push with explicit past timestamps via Loki's push API in batches, ascending
  per stream.
- Loki rejects old samples by default — set `reject_old_samples: false` (or
  `reject_old_samples_max_age: 336h`) in `limits_config`.
- **Do not shrink `max_chunk_age` to make flushes faster.** It also sets the
  out-of-order acceptance window. Use `chunk_idle_period: 1m` for that instead,
  and leave `max_chunk_age` at `2h`.
- Backdated data is not instantly queryable: the ingester holds the chunk, but
  the series is not findable for that day until the TSDB index is uploaded.
  Measured here: about 80 seconds. Re-seed well before the session, not at
  T-minus-two-minutes.
- Anchor all timestamps relative to *run time*, not absolute dates, so
  "yesterday" is always yesterday no matter when you re-seed.
- Keep the live generators running too, so the most recent hour is genuinely
  live and `make step-05`'s "errors in the past 24h" report is never empty.
