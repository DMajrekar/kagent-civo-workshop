# Your Cluster Called

*and it's found a problem*

A 60-minute hands-on workshop: kagent on Civo, backed by relax.ai.

17 slides. The machine needs about eight minutes of the hour — these slides are the air cover around it, so most are on screen for several minutes at a time.

Speaker notes are the run of show: timings, what to say during the 30–80 second agent waits, and the cut-lines.

---

# Act one

*Getting started*

---

## 1. Title

**Label:** kagent on Civo · 60 minutes

### Headline

> Your Cluster Called
> and it's found a problem

*Title slide — set this large.*

### On the slide

```text
Get set up while you wait:   wall-74-220-17-251.sslip.io/join
Passphrase:  kagent-sept-22
```

### Speaker notes

> HOLDING SLIDE — up as people arrive, so early arrivals can start.
> Advance when you're ready to begin.

---

## 2. The hook

### Headline

> “Checkout started returning 502s four days ago.
> It lines up with a deploy.
>
> Something's exhausting the orders database
> connection pool every night at 2am.
>
> Also — your auth certificate expires in nine days.”

### On the slide

```text
Nobody told it to look for any of that.
```

### Speaker notes

> 30 seconds. Read it, pause on the certificate line, then the payoff.
>
> Do NOT explain how yet. They're going to build the thing that said it,
> and the whole session works better if they get there themselves.

---

## 3. Get your credentials

**Label:** do this now

```
wall-74-220-17-251.sslip.io/join
```

### On the slide

```text
Passphrase:  kagent-sept-22

Name, your Civo key, download the .env.
Your Civo key never leaves your browser.
```

### Speaker notes

> LEAVE THIS REACHABLE ALL SESSION — people will ask twice.
> ~3 minutes. Walk the room.
>
> Same name always returns the same credentials, so reloading is safe.
> No Civo account? dashboard.civo.com, free signup.
>
> Then get everyone to start their cluster before you talk.

---

## 4. Two clusters, one protocol

**Label:** what you're building

### On the slide

```text
YOURS                                    MINE
  an agent that can reason        a platform you've never seen
  and call tools                          seven days of its logs

                     ── MCP ──▶
```

### Speaker notes

> Keep this light — 90 seconds. They'll see the detail live.
>
> The one point worth making: everything on the left is theirs and they
> keep it. The thing on the right is mine, and it's a platform that has
> been misbehaving for a week.
>
> LIVE: start step-01 here if you haven't. It returns immediately.

---

# Act two

*Background — air cover while clusters build*

---

## 5. An agent is a Kubernetes resource

**Label:** background

### On the slide

```text
ModelConfig          what it thinks with

Agent                what it's for, and what it may touch

RemoteMCPServer      where its tools come from

kubectl get agents. Review it, diff it, roll it back.
```

### Speaker notes

> ~3 min of air cover while clusters provision.
>
> The point: this isn't a chatbot bolted onto Kubernetes. It's a workload
> with an identity, RBAC and a manifest — the things you already know how
> to reason about.
>
> Good question for the room: who already runs something that reads logs
> at 3am? Right — same job, different implementation.

---

## 6. Why in the cluster at all?

**Label:** background

### On the slide

```text
It already has the credentials, the network reach, the RBAC.

When it acts, it acts as an identity you granted —
not a token someone pasted into a laptop.
```

### Speaker notes

> ~2 min. This is the actual argument for the approach; make it properly.
>
> LIVE: by now step-02 and step-03 should be running. Show your own
> console — the ModelConfig is one baseUrl field pointing at relax.ai.
> Let someone read out what their agent said about their own cluster.

---

## 7. MCP: tools an agent can find for itself

**Label:** background

### On the slide

```text
Your agent has no idea what Loki is.

It connects, asks what tools exist, and decides which to use.

A driver, not an integration. You don't rebuild the agent
to give it new senses.
```

### Speaker notes

> ~2 min, immediately before they connect to the hub.
>
> This is the conceptual unlock. If they get this, step-04 lands.
> If you only make one point in the whole session, make this one.

---

## 8. Eight services, seven days

**Label:** over to you

### Headline

> Eight services. Seven days.
> Nobody has told it what's wrong.

### On the slide

```text
web · api-gateway · checkout · orders-db-proxy
search · image-resizer · notifications · auth

Some of this is healthy. Some of it isn't.

Go and find out which.
```

### Speaker notes

> THIS IS THE SESSION. Give it 12-15 minutes and get out of the way.
>
> Do NOT hand them questions. Let them interrogate it. Walk the room,
> read over shoulders, pull good findings up on the projector.
>
> There are six things genuinely in there — your answer key:
>   · checkout 502s stepping up after a v2.3.1 deploy, 4 days ago
>   · orders-db-proxy pool exhaustion, nightly 02:00-02:40
>   · image-resizer OOMKill loop, worsening over 2 days
>   · notifications = 45% of all log volume, debug left on
>   · auth TLS certificate expiring in 9 days, nothing failing yet
>   · search p99 creeping up ~8%/day with zero errors
>
> If the room stalls, nudge with a THEME not a prompt: 'has anything
> changed this week?' / 'anything on a schedule?' / 'anything about to
> break that hasn't yet?'
>
> Backstop, only if it's really flat — the verbatim prompt that finds
> the certificate: 'Is there anything that will fail in the next two
> weeks but is not failing today?'

---

# Act three

*Closing — what they take away*

---

## 9. Now go and find it yourself

**Label:** closing

```
logs-74-220-17-251.sslip.io
```

### On the slide

```text
Same Loki. Same seven days. No agent.

Anonymous, read-only — open it and try.
```

### Speaker notes

> DO THIS LIVE, and take your time fumbling. It is the strongest
> argument in the session and it makes itself.
>
> Open Explore, pick the Loki datasource, and try to find the auth
> certificate expiry. To get there you need to know: that Loki uses
> LogQL, that you want a label selector on service, that the line is
> at warn not error, and — the real problem — that certificates are
> a thing worth looking for at all.
>
> Everything the agent found is sitting right there. None of it is
> hidden. The difference is knowing what to ask.
>
> Let a couple of attendees try on the projector if they will.
> Nobody finds the certificate. That is the point -- it is the one
> incident where nothing is failing yet, so nothing draws your eye.
>
> Then move to the next slide and collect what they DID find with
> the agent.

---

## 10. So what did you find?

**Label:** closing

### Speaker notes

> COLLECT FROM THE ROOM. 5 minutes, and resist filling the silence.
>
> Ask who found something nobody else did. Ask if anyone's agent got
> something wrong. Both are useful.
>
> You're fishing for the three learnings on the next slides — if the room
> says them first, that's a better session than you saying them.

---

## 11. The question did the work

**Label:** closing · learning

### On the slide

```text
“Is anything about to break?”
     → the crash loop. Everything else looks fine.

“…but is not failing today?”
     → the certificate, with nine days' notice.

Same data. Same model.
```

### Speaker notes

> The most transferable thing in the session.
>
> The second phrasing makes it exclude what's already failing, so it has
> to reason about the future instead of ranking the present.
>
> If someone in the room discovered this themselves, credit them and let
> them explain it.

---

## 12. Check its work

**Label:** closing · learning

### On the slide

```text
In testing it once blamed the wrong service for a deploy —
right finding, wrong attribution.

It's a very fast colleague who has read everything
and is sometimes confidently wrong.
```

### Speaker notes

> Be straight about this; it lands far better than pretending.
>
> The useful framing: this doesn't replace the on-call engineer, it gets
> them to the right three questions in thirty seconds instead of an hour.
>
> LIVE: show the wall here as the daily reports land.

---

## 13. It's just a workload

**Label:** closing · learning

### On the slide

```text
No console. No vendor. No agent platform.

A Deployment, a Secret, a CronJob and a URL —
reviewed, diffed and rolled back like anything else you run.
```

### Speaker notes

> The architectural takeaway, and the one that outlives the demo.
>
> Worth saying: swap relax.ai for a self-hosted model by editing one
> field. Swap Loki for whatever you already run, if it speaks MCP.

---

## 14. Prompts worth stealing

**Label:** take these with you

### On the slide

```text
What changed in the last 24 hours that wasn't happening last week?

Anything failing on a schedule? Group by hour of day, not by count.

Group today's errors by likely root cause, not by message.

If I were paged right now, what would you check first — and why
that rather than the others?

Is anything degrading slowly enough that nobody has noticed?
```

### Speaker notes

> Point out these are SHAPES, not magic strings — their dataset is gone
> when the hub goes, but the question forms transfer.
>
> Two habits worth calling out:
>   · Ask for reasoning — 'and why that rather than the others' turns a
>     list into something you can argue with.
>   · Put your context in the system prompt, not the question. It doesn't
>     know which of your services matter or what normal looks like.
>
> All of these are in docs/AFTER.md so nobody has to photograph the slide.

---

## 15. Where to take it next

**Label:** take these with you

### On the slide

```text
Point log-detective at your own logs — one field on the RemoteMCPServer

Rewrite the system prompt for your services — most of the quality is there

Move it to a Monday digest — a daily nobody reads is worse than nothing

Add a second MCP server: Prometheus, GitHub, PagerDuty

Let it act, behind approval — start with something reversible

Split it in two — you already have two; a triage agent routes to them
```

### Speaker notes

> In rough order of effort. The first one is where nearly all the value
> is and takes ten minutes — push it hardest.
>
> The second is the one people get wrong: they ship a daily report,
> nobody reads it by week two, and they conclude agents don't work.
>
> Third is where it stops being a log summariser and starts correlating
> — a deploy in GitHub against an error spike in Loki.
>
> examples/my-agent.yaml is a commented scaffold for all of this.

---

## 16. You're keeping this

**Label:** before you go

### On the slide

```text
It bills to YOUR Civo account.

cluster-scout keeps working forever. log-detective loses its log
tools when my hub goes on 22 October — repointing it at logs of
your own is one field.

Your relax.ai key is yours to keep.
```

### Speaker notes

> SAY THE BILLING LINE OUT LOUD. An unexpected charge next month is the
> one thing that turns a good workshop into a complaint.
>
> make clean deletes the cluster and its volumes.
> civo kubernetes scale <name> --nodes=1 halves it instead.
>
> On 22 October: only log-detective is affected, and the fix is one
> URL on the RemoteMCPServer pointed at their own Grafana. That is a
> better ending than running a copy of my fake platform — it sends
> them at their real systems. docs/AFTER.md has the command.
>
> Put 22 October in the follow-up email as well as on this slide.

---

## 17. Everything is in the repo

**Label:** thank you

```
github.com/dmajrekar/kagent-civo-workshop
```

### On the slide

```text
Those prompts and next steps:  docs/AFTER.md

kagent.dev  ·  civo.com  ·  relax.ai
```

### Speaker notes

> Leave up for Q&A.
>
> Likely questions: what does this cost to run for real; can it act as
> well as read (yes, with approval); does it work with self-hosted models
> (yes — one field); what if we don't run Loki (any MCP server works).
