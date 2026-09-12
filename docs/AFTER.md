# Keeping it after the workshop

You're leaving with this cluster running, which means you need to know two
things: **what still works tomorrow**, and **what it costs**.

## What breaks, and when

Your agent depends on one thing you don't own: the workshop hub.

| Dependency | Lifetime | What happens when it ends |
|------------|----------|---------------------------|
| The hub's MCP endpoint | **until 2026-10-22** | Agent loses its log tools. It still answers and can still see your own cluster, but the seven-days-of-logs trick stops working. |
| Your relax.ai key | Yours — check with relax.ai for quota | Nothing, unless you exhaust the quota |

So nothing breaks the day after the workshop. But put **2026-10-22** in your
calendar now, because in a month you will not remember why your agent suddenly
got less useful.

`make step-06` cuts the cord ahead of that date. There's no rush — but it takes
about two minutes, and doing it while the workshop is fresh is easier than
reverse-engineering it in five weeks.

## Cutting the cord

### 1. Your relax.ai key

The key on your workshop card is yours — it isn't shared with anyone else and
it isn't rotated after the event. Check your quota at
[relax.ai](https://relax.ai); if you need to swap it for another one later:

```bash
kubectl -n kagent create secret generic kagent-relax \
  --from-literal=RELAX_API_KEY=<your-key> \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n kagent rollout restart deploy/kagent
```

Nothing else changes — the `ModelConfig` already points at that secret by name.

### 2. Your own logs

The hub was a fleet of deliberately broken services. You can run a small
version of it in your own cluster:

```bash
make step-06            # deploys Loki + mcp-grafana + the log generators
```

This deploys the same stack the hub ran, sized for one cluster, and repoints
your `RemoteMCPServer` at `http://mcp-grafana.observability:8000/mcp` instead
of the hub. Same tools, same agent, no external dependency — and it keeps
working after 2026-10-22.

If you'd rather point it at logs you actually care about, swap the Loki URL in
the `mcp-grafana` Deployment for your own Grafana or Loki — the agent doesn't
care where the data comes from.

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

`workshop/step-06-extend/my-agent.yaml` is a commented scaffold to start from.
