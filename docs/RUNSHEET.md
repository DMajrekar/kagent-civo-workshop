# Run sheet

Format: a capture-the-flag in two twenty-minute rounds. Players are on their
own phones over mobile data; there is no venue wifi and nothing to install.
You are on a laptop with a connection of your own (a tethered phone is fine).

Allow about fifty-five minutes end to end.

## In the room

| Time | What | On the projector | You do |
|------|------|------------------|--------|
| 00:00 | Welcome. How an alert gets handled, and what the logs already knew. Then what Grafana looks like. | deck | — |
| 00:02 | Everyone joins | QR code slide, then deck: the live scoreboard (names appear as they join) | Wait until the count stops climbing. |
| 00:05 | **Round one — Grafana** | deck: the live scoreboard | `/admin` → *Start round 1*. Say the logs are in UTC. |
| 00:25 | Time. What did people find? What did nobody find? | deck: the live scoreboard | Look at which columns are empty. They will be the last two. |
| 00:27 | What kagent is. An agent is a model, a prompt and some tools. | deck | — |
| 00:29 | A cluster, then kagent going on to it | deck: six recordings, full screen | Two for the cluster, four for the install. Each holds its last frame until you move on. |
| 00:30 | Three agents: no briefing, a good briefing, a specialist | deck: a slide then a recording for each | The diff between agent 1 and 2 is all prompt. Say so. |
| 00:33 | **Round two — kagent** | deck: the live scoreboard | `/admin` → *Start round 2*. |
| 00:53 | Time. Read the scoreboard together. | deck: the live scoreboard | `/admin` → *Finish*. |
| 00:55 | Close | deck: the live scoreboard | — |

**The projector stays on the deck.** The scoreboard slides are the real
`/board`, live, framed in the deck, so there is no window to switch to. You
still start and stop the rounds from `/admin`, on your phone or in another
window. If the deck's address is ever unreachable, `/board` itself still works.

**Nothing is built live.** The hub, kagent and all three agents exist before
the room arrives. What the deck shows between the rounds are recordings of
those same steps being run for real against this hub (`make record`), played
full screen. Players cannot see the agents until round two starts, so the
reveal still happens when you press the button.

If you would rather do it live, you can: `make agents-clear` beforehand, then
`make agent-01` and so on in a terminal instead of playing the recordings.
Each takes twenty to forty seconds to become ready, so do it before you start
the clock.

## What to say at the scoreboard

The two big numbers at the top are flags found per round. They are the
headline, but the grid underneath is the argument:

- **The left-hand columns are mostly blue.** Grafana is perfectly good at
  "which service is loudest". Say so. The agent did not make that easier.
- **The right-hand columns are mostly orange, or empty.** A service that is
  slowing down with no errors, and a certificate that has not expired yet.
  Nothing was hidden — every one of those lines was in Grafana for twenty
  minutes. The difference was knowing what to ask.
- **Some people did better with `log-reader` than others did with
  `log-detective`.** The quality of the answer is mostly the quality of the
  question. That is the most transferable thing in the session.

Be straight about the comparison: round two has a head start, because people
have had twenty minutes with the data already. It is a demonstration, not an
experiment, and someone in the room will say so if you do not.

## Before the day

Build the hub at least a day ahead and leave it running. Then play it
yourself, **on a phone, on mobile data, with wifi turned off**:

- [ ] Join with an email. You get a handle and an empty flag sheet.
- [ ] Join again in a private window with a second email. Two rows on `/board`.
- [ ] `/admin` → start round one. Both phones show the flags within five seconds.
- [ ] Open Grafana from the page. Explore loads, on the Loki datasource, last 7 days.
- [ ] Solve `volume` by hand. The card goes green; `/board` shows a blue square.
- [ ] Try to open the kagent address directly. You are sent back to the CTF page.
- [ ] In round two, open an agent, then change the address to `/agents` or
      `/models`. You are sent back to the CTF page: only the chat is reachable.
- [ ] `make agent-01`, `agent-02`, `agent-03`. Players see none of them yet.
- [ ] Start round two. All three agents appear on both phones.
- [ ] Ask it something. An answer streams back.
- [ ] **On the second phone, open kagent. The first phone's chat is not there.**
- [ ] In kagent's own UI, try to edit or delete the agent. It is refused.
- [ ] Solve a flag. `/board` shows an orange square.
- [ ] Restart the CTF pod (`kubectl -n observability rollout restart deploy/ctf`).
      Scores and the clock survive.
- [ ] Ask the relax.ai team for the rate limit on your key (docs/CAPACITY.md).
- [ ] `make record`, then `make hub-10`, and watch all nine recordings on their
      slides at the deck's address. Do this last: it uninstalls and reinstalls
      kagent (wiping its chat history), deletes and recreates each agent, and
      creates and destroys a second cluster for the Terraform recording.
- [ ] Scan the QR code on the join slide with a phone. It opens this hub.

The two in bold are the ones the automated checks cannot fully make for you.
`make hub-08` proves chat privacy against kagent's API; only a browser proves
the dashboard passes the player's identity along on every call it makes.

On the morning: `make hub-05` re-seeds the dataset so that "the last seven
days" ends today. Do it at least ten minutes before the session.

## When something breaks

| If… | Do this |
|-----|---------|
| A player has no signal | Pair them with a neighbour. There is no offline mode. |
| Someone joins late | Nothing to do. Late joiners see the current round immediately. |
| A player loses their page | Same email gets the same player back, score and all. |
| Grafana is slow when round one starts | Expected for the first half minute: it is the whole room running a 7-day query at once. `/admin` → *+1 minute* if it costs real time. |
| An agent is not ready on the day | `kubectl -n kagent describe agent <name>`. Carry on with the ones that are; the page only offers agents that are ready. |
| Agents answer with rate-limit errors | The room has hit the relax.ai limit on the shared key. Tell people to take turns; there is no faster fix in the room. |
| The CTF page is down | `kubectl -n observability rollout restart deploy/ctf`. State is on a volume. |
| You need to rerun a round | `/admin` → *Start round N* again restarts its clock. Solves are kept. |
| You want a clean slate | `/admin` → *Reset* → *Wipe scores*. Players stay joined. |
| Your own connection dies | The game carries on without you; players do not go through your laptop. You only need it to change rounds and add agents — do both from a phone browser and a second terminal if you must. |

## Afterwards

- `/admin` → *Download emails* gives a CSV of email, handle and score.
- `make hub-99` deletes the cluster and everything on it, including that list.
- The hub costs money for every hour it is up. It is not designed to be left
  running: the kagent dashboard is only as private as the CTF app's sessions.
