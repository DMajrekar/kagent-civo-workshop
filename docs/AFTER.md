# Keeping it after the workshop

You're leaving with this cluster running, which means you need to know two
things: **what still works tomorrow**, and **what it costs**.

## What breaks, and when

| | Lifetime | What happens when it ends |
|---|---|---|
| `cluster-scout` | yours, indefinitely | nothing — it only ever needed your own cluster |
| `log-detective` | **the log tools stop on 2026-10-22** | it keeps answering, but loses its view of the log platform |
| Your relax.ai key | yours — check with relax.ai for quota | nothing, unless you exhaust the quota |

So nothing breaks the day after the workshop. Put **2026-10-22** in your
calendar, because in a month you will not remember why one of your agents got
less useful.

## Pointing it at your own logs

When the hub goes, don't replace it with a copy of a fake platform — point the
agent at logs you actually care about. It is one field.

`log-detective` reaches the hub through a `RemoteMCPServer` called
`workshop-logs`. Swap the URL for an MCP server in front of your own Grafana:

```bash
kubectl -n kagent edit remotemcpserver workshop-logs
#   spec.url: https://<your-mcp-grafana>/mcp
```

If you don't already run one, `mcp-grafana` is a single Deployment pointed at
a Grafana instance with `GRAFANA_URL` and a service-account token — the hub
runs exactly that, and `hub/step-06-mcp/` in this repo is a working example
including the bearer-token proxy in front of it.

Everything else stays as it is. Same agent, same model, same prompt: it just
looks somewhere real instead.

If you would rather it stopped asking about logs at all, delete the second
entry under `tools` in the Agent and re-apply — it goes back to being a
cluster agent like `cluster-scout`.

## What it costs

Your cluster bills to **your** Civo account until you delete it. Check the
current rate for your node size before you walk away:

```bash
civo kubernetes size          # per-node hourly/monthly rates
civo kubernetes ls            # what you currently have running
```

Two `g4s.kube.medium` nodes is a modest monthly spend, not a rounding error.
Set a billing alert in the Civo dashboard, or scale to a single node:

```bash
civo kubernetes scale <cluster> --nodes=1
```

When you're done with it:

```bash
make clean
```

## Prompts worth stealing

The workshop prompts were tuned to a dataset you no longer have. These are the
*shapes* that worked, pointed at logs you actually care about.

The single most useful trick, and the one the session turns on: **say what to
exclude.** "Is anything about to break?" ranks whatever is loudest right now.
"…that isn't already failing" forces it to reason about the future instead.

```
What changed in the last 24 hours that wasn't happening the week before?

Anything failing on a schedule? Group errors by hour of day, not by count.

Which service is producing the most log volume, and is any of it worth keeping?

Group today's errors by likely root cause rather than by message.

If I were paged right now with no other context, what would you have me
check first, and why that rather than the others?

Is anything degrading slowly enough that nobody has noticed — getting worse
every day but not yet failing?

What is failing quietly? Retried, recovered, and never alerted on.

Is there anything that will break in the next two weeks but is fine today?
```

Two habits worth keeping:

- **Ask for reasoning, not just findings.** "and why that rather than the
  others" turns a list into something you can disagree with.
- **Give it your context in the system prompt, not the question.** It has no
  idea which of your services matter, what your normal looks like, or what
  you were paged for last week. Tell it once, in the Agent, rather than every
  time you ask.

## Where to take it next

The agent you built is a starting point, not a finished thing. In rough order
of effort:

1. **Ask it better questions.** Most of the value is in the prompt. Edit the
   `systemMessage` in `workshop/step-03-agent/agent.yaml` to give it context
   about *your* services and what "bad" looks like for you.
2. **Change the schedule.** The CronJob runs daily. A Monday-morning weekly
   digest is often more useful than a daily one nobody reads.
3. **Add a second MCP server.** Prometheus, GitHub, PagerDuty — anything with
   an MCP server becomes a tool your agent can reach for. This is where it
   stops being a log summariser and starts correlating.
4. **Give it write access, behind approval.** kagent can act on the cluster,
   not just read it. Start with something reversible and keep a human in the
   loop.
5. **Run more than one agent.** You already do — `cluster-scout` and
   `log-detective` are deliberately separate. A triage agent that routes to
   specialists works better than one agent that knows everything.

`examples/my-agent.yaml` is a commented scaffold to start from.
