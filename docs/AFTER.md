# Keeping it after the workshop

You're leaving with this cluster running, which means you need to know two
things: **what still works tomorrow**, and **what it costs**.

## What breaks, and when

During the workshop your agent depended on two things you don't own:

| Dependency | Lifetime | What happens when it ends |
|------------|----------|---------------------------|
| The hub's MCP endpoint | ~7 days after the event | Agent loses its log tools; it still answers, but can only see your own cluster |
| The shared relax.ai key | Rotated the evening of the event | Agent stops responding entirely — every call 401s |

`make step-06` cuts both cords. Run it before you leave if you can; run it at
home if we ran out of time.

## Cutting the cord

### 1. Your own relax.ai key

The workshop key is shared across the room and gets rotated straight after.
Sign up at [relax.ai](https://relax.ai), then:

```bash
kubectl -n kagent create secret generic kagent-relax \
  --from-literal=RELAX_API_KEY=<your-own-key> \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n kagent rollout restart deploy/kagent
```

Nothing else changes — the `ModelConfig` already points at your own secret.

### 2. Your own logs

The hub was a fleet of deliberately broken services. You can run a small
version of it in your own cluster:

```bash
make step-06            # deploys Loki + mcp-grafana + the log generators
```

This deploys the same stack the hub ran, sized for one cluster, and repoints
your `RemoteMCPServer` at `http://mcp-grafana.observability:8000/mcp` instead
of the hub. Same tools, same agent, no external dependency.

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
5. **Run more than one agent.** A triage agent that routes to specialists
   works better than one agent that knows everything.

`workshop/step-06-extend/my-agent.yaml` is a commented scaffold to start from.
