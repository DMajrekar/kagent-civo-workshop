# Your cluster called — a kagent CTF on Civo

A capture-the-flag in a week of production logs, played twice. For twenty
minutes the room has **Grafana**. Then the instructor unlocks **kagent**, and
for twenty more the room has agents. Same logs, same flags, one scoreboard
that shows which tool found what.

**Players need a phone and nothing else.** No laptop, no install, no venue
wifi — everything runs on one Civo cluster and is reached over mobile data.

**Backed by:** [kagent](https://kagent.dev) · [Civo Kubernetes](https://civo.com)
· [relax.ai](https://relax.ai) · Grafana Loki over MCP

---

## How it plays

1. **Join.** Scan the QR code, enter an email, get a flag sheet and a handle.
2. **Round one — Grafana.** Twelve questions about a fictional platform that
   has been misbehaving all week. The page links straight into Grafana Explore.
3. **The swap.** The deck shows kagent and three agents being built, then the
   instructor starts round two and the agents appear on every player's page.
4. **Round two — kagent.** Same flags, carrying on from wherever Grafana left
   each player, now with the real kagent dashboard.
5. **The scoreboard** is on the projector throughout. Every solved flag is
   coloured by the round it fell in.

```
   a phone, on mobile data                 the hub (one Civo cluster)
   ┌───────────────────┐                   ┌──────────────────────────────┐
   │  CTF page         │──── https ───────▶│  CTF app    flags, clock,    │
   │                   │                   │             scores           │
   │  Grafana Explore  │──── https ───────▶│  Grafana ─▶ Loki, 7 days of  │
   │                   │                   │             logs, 8 services │
   │  kagent dashboard │──── https ───────▶│  kagent  ─▶ agents ─ MCP ─┘  │
   └───────────────────┘   (round two)     └──────────────────────────────┘
```

## Running one

You need a Civo API key and a relax.ai key.

```bash
cp .env.example .env      # add both keys
make hub-all              # builds everything
make agent-01             # and agent-02, agent-03
make status               # the addresses, and your admin key
make record               # terminal recordings for the slides
make hub-10               # again, to put the recordings in the hosted deck
```

Then, in the room:

| | |
|---|---|
| Players | the CTF address, as a QR code on a slide |
| Projector | `/board` |
| You | `/admin` — start round one, start round two, finish |
| The deck | hosted on the hub; `make status` prints its address |
| Between the rounds | the deck: recordings of kagent and the agents being built |

[`docs/RUNSHEET.md`](docs/RUNSHEET.md) is the minute-by-minute plan, the
rehearsal checklist and what to do when something breaks.

## Sharing one kagent with a room

kagent's dashboard has no login. Put it on the internet as it comes and every
visitor is the same user, reads every chat, and has a Delete button on the
agent. Three things stop that here:

- **Identity.** The ingress asks the CTF app about every request to kagent.
  The answer names the player, and kagent files their chats under that name —
  so nobody sees anyone else's, including the answers.
- **A guard.** The dashboard's API calls go through a small nginx
  (`hub/step-08-kagent/guard.conf`) that passes reads and conversations and
  refuses everything else. Agents can only be changed with `kubectl`.
- **Nothing to steal.** The chart's built-in agents and Kubernetes tools are
  not installed. The only tool an agent here can have is the read-only log
  endpoint.

`make hub-08` and `make hub-09` test each of these and stop if one fails.

## Repository layout

| Path | What |
|------|------|
| `hub/step-*/` | Builds the hub. One `run.sh` each, idempotent. |
| `hub/step-07-ctf/ctf.py` | The whole CTF app: join, flags, scoreboard, round control. |
| `hub/step-08-kagent/` | kagent's values and the guard. |
| `hub/step-10-slides/` | Builds the deck on the hub and serves it. |
| `slides/` | The deck's source. |
| `agents/` | The agents you add during the session. Edit, add or remove freely. |
| `docs/RUNSHEET.md` | The plan for the session. |
| `docs/INCIDENTS.md` | The seeded dataset, its six incidents and the twelve flags. |
| `docs/CAPACITY.md` | How many players it takes, and what is still unmeasured. |
| `docs/DEMO-PROMPTS.md` | Questions known to find each incident. |

## Changing it

- **Flags** are the `FLAGS` list at the top of `ctf.py`. Keep
  `docs/INCIDENTS.md` in step; CI fails if they disagree.
- **Agents** are plain kagent `Agent` manifests in `agents/`. The number prefix
  is only the order `make help` lists them in.
- **Round length** is `ROUND_SECONDS` in `.env` (default 1200).

`DEMO_AUTO=1` runs any step without the press-enter pauses.
