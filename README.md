# kagent on Civo — workshop

Build a working AI agent that lives inside your own Kubernetes cluster, can
reason about seven days of production logs, and files you a report every
morning. You leave with a cluster and a repo you can keep extending.

**Backed by:** [kagent](https://kagent.dev) · [Civo Kubernetes](https://civo.com)
· [relax.ai](https://relax.ai) · Grafana Loki over MCP

---

## Before the workshop (10 minutes, please do this in advance)

```bash
git clone <this-repo> && cd kagent-workshop
cp .env.example .env      # then fill in the values from your workshop card
make doctor
```

`make doctor` must print all green. **If it doesn't, get in touch before the
day** — there isn't time to debug laptop setups during a 60-minute session.

## On the day

```bash
make            # see every step
make step-01    # create your Civo cluster
make step-02    # install kagent, point it at relax.ai
make step-03    # your first agent
make step-04    # give it seven days of logs over MCP
make step-05    # a CronJob that reports every morning
make step-06    # cut the cord — your own key, your own logs
```

Every step is idempotent — if one fails, fix the cause and run it again. If you
fall behind, don't catch up; run the step everyone else is on.

**You keep this cluster.** It bills to your own Civo account, and the workshop
credentials are temporary — [`docs/AFTER.md`](docs/AFTER.md) covers what expires,
what it costs, and how to make it permanently yours. `make clean` deletes
everything when you've had enough.

## What you're building

```
   your cluster                         the workshop hub
   ┌──────────────────────┐             ┌────────────────────────┐
   │  kagent              │             │  Loki   7 days of logs │
   │    ├─ Agent ─────────┼── MCP ─────▶│  Grafana + mcp-grafana │
   │    │   └─ relax.ai   │             │  8 misbehaving services│
   │    └─ CronJob ───────┼── webhook ─▶│  the wall              │
   └──────────────────────┘             └────────────────────────┘
```

Your agent runs in your cluster and talks to two things: **relax.ai** for
reasoning, and the **hub's MCP endpoint** for logs. The hub is shared — it's a
fleet of deliberately broken applications that have been failing in interesting
ways for a week. Your job is to get your agent to notice.

## Repository layout

| Path | What |
|------|------|
| `workshop/step-*/` | The attendee steps. One `run.sh` each. |
| `hub/step-*/` | Instructor only — builds the shared observability hub. |
| `scripts/lib.sh` | The presentation runner (`run`, `pause`, `wait_for`). |
| `docs/RUNSHEET.md` | Minute-by-minute plan for the hour. |
| `docs/BUILD-PLAN.md` | What gets built before the event, in risk order. |
| `docs/INCIDENTS.md` | The seeded dataset and its six planted incidents. |
| `docs/WEBHOOK-SINK.md` | The report sink and the wall view. |
| `docs/AFTER.md` | Keeping your cluster working after the event. |

## Notes for anyone re-running this

Set `DEMO_AUTO=1` to run any step without the press-enter pauses — `make
rehearse` does this for the whole workshop, and is the only reliable way to
know the thing still works before you stand up in front of people.
