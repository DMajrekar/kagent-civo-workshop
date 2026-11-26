# Standing up the environment

How to build everything the workshop runs on, for whoever is hosting it. The
session itself — timings, what to say, what to do when something breaks — is
in [`RUNSHEET.md`](RUNSHEET.md).

Everything lives on one Civo cluster, "the hub": Loki with a week of seeded
logs, Grafana, the CTF app, a kagent the room shares, and the slide deck.
Attendees need a browser and nothing else.

## What you need

On your machine:

| Tool | For |
|---|---|
| `civo`, `kubectl`, `helm`, `jq`, `python3`, `curl` | building the hub |
| `asciinema`, `agg` | `make record`, the terminal recordings in the deck |
| `terraform` | `make record N=0` only, the cluster-creation recording |
| `gh` | nothing here; only if you are opening pull requests |

Node and Docker are not needed. The deck is built in a container on the hub.

On a fresh Ubuntu server, one script installs all of it:

```bash
sudo scripts/install-prereqs.sh              # add WITH_GH=1 for the GitHub CLI
```

It pins the versions the workshop was last built with and leaves alone
anything already installed.

Two keys, in `.env`:

```bash
cp .env.example .env
```

| Setting | Notes |
|---|---|
| `CIVO_API_KEY` | From the Civo dashboard. |
| `CIVO_REGION` | The region nearest the venue. |
| `RELAX_API_KEY` | One key serves the whole room. |
| `RELAX_BASE_URL` | Only if the key is for a different endpoint. The November 2026 event used `https://api.beta.relax.ai/v1`; a key for one endpoint is refused by the other. |
| `ACME_EMAIL` | Where Let's Encrypt sends expiry notices. |
| `HUB_DOMAIN` | Optional. Without it the addresses are `sslip.io` names built from the ingress IP, which need no DNS. |
| `ROUND_SECONDS`, `ROUND2_SECONDS` | Round lengths. Defaults are 600 and 900. |

## Build it

Do this at least a day ahead and leave it running.

```bash
make hub-all        # every step below, in order
make agent-01       # log-reader
make agent-02       # log-detective
make agent-03       # early-warning
make status         # the addresses, and your admin key
```

Every step is idempotent and checks its own work. If one fails, fix the cause
and run the same target again. `DEMO_AUTO=1` skips the press-enter pauses.

| Step | What it does |
|---|---|
| `hub-01` | Creates the cluster: three medium nodes, plus one larger node for Loki. |
| `hub-02` | Loki, pinned to the larger node. |
| `hub-03` | Grafana, with Loki as its datasource. |
| `hub-04` | The eight fictional services that generate logs. |
| `hub-05` | Wipes Loki, backfills seven days of history ending now, and validates that every incident is findable. |
| `hub-06` | mcp-grafana behind a bearer-token check: the agents' only tool. |
| `hub-07` | The CTF app: join, flags, scoreboard, round control. |
| `hub-08` | kagent, the guard in front of it, and the log tool server. Tests that players can chat and do nothing else. |
| `hub-09` | Public HTTPS addresses for the CTF, Grafana and kagent. |
| `hub-10` | Builds the deck on the hub and serves it. |
| `hub-99` | Deletes the cluster and its volumes. |

Players cannot see the agents until you start round two, so adding them ahead
of time gives nothing away.

## The deck and its recordings

```bash
make record         # needs asciinema, agg and terraform
make hub-10         # rebuild the hosted deck with the new recordings
```

`make record` uninstalls and reinstalls kagent, deletes and recreates the
agents, and creates and destroys a second cluster for the Terraform recording.
It wipes kagent's chat history, so do it before anyone is using the hub.
[`slides/README.md`](../slides/README.md) has the detail, including the Grafana
screenshots and what to edit in `slides/src/event.js` for each event.

Run `make hub-10` again after any change under `slides/`.

The agent recordings show each agent being applied and becoming ready. They
do not show the manifest or an answer, so they only need redoing if that
output changes. `make record N="2 3 4"` needs only `hub-01` to `hub-04`,
`hub-06` and `hub-08` to have run.

## Before each event

1. **Change the flag answers if the room may have seen this repo.** It is
   public, and `hub/step-07-ctf/ctf.py` and `docs/INCIDENTS.md` contain every
   answer. The answers are names, versions and hours in the `FLAGS` list and
   the seeded dataset; keep the two in step (CI fails if they disagree).
2. **Rehearse** with the checklist in [`RUNSHEET.md`](RUNSHEET.md). Test from
   a phone on mobile data even if the venue has wifi: it is the hardest case.
3. **For a much larger room than 18, read [`CAPACITY.md`](CAPACITY.md)** and
   ask relax.ai about the rate limit on your key.
4. **On the morning, `make hub-05`**, at least ten minutes before the session.
   It re-seeds the dataset so that "the last seven days" ends today.

## How one kagent is shared with a room

kagent's dashboard has no login. Put it on the internet as it comes and every
visitor is the same user, reads every chat, and has a Delete button on the
agent. Four things stop that here:

- **Identity.** The ingress asks the CTF app about every request to kagent.
  The answer names the player, and kagent files their chats under that name,
  so nobody sees anyone else's.
- **Chat only.** The same check lets a player load an agent's chat page and
  nothing else. The pages for creating agents, models and tool servers send
  them back to the CTF page.
- **A guard.** The dashboard's API calls go through a small nginx
  (`hub/step-08-kagent/guard.conf`) that passes reads and conversations and
  refuses everything else. Agents can only be changed with `kubectl`.
- **Nothing to steal.** The chart's built-in agents and Kubernetes tools are
  not installed. The only tool an agent here can have is the read-only log
  endpoint.

`make hub-08` and `make hub-09` test each of these and stop if one fails.

## The model

The agents run `DeepSeek-V41-Flash` with reasoning off
(`reasoningEffort: none` in `hub/step-08-kagent/values.yaml`) and stream their
answers (`stream: true` in each agent). With reasoning on, an answer took
three to five minutes; with it off, thirty to ninety seconds, and it still
found every incident. The comparison with the other models is in
[`DEMO-PROMPTS.md`](DEMO-PROMPTS.md).

Set `RELAX_MODEL` in `.env` to try another, then `make hub-08`.

## What the first event taught us

November 2026, 18 players.

- **Most of the room used the venue's wifi, on laptops as well as phones.**
  It was designed for no wifi and still works that way.
- **Ten minutes of Grafana and fifteen of kagent was enough.** Flags carry
  over from round one to round two; they are not reset.
- **Speed came from the model settings, not the cluster.** Loki answered tool
  calls in under half a second throughout. See "The model" above.
- **Speed was not an issue.** Nobody in the room remarked on how long answers
  took, and the relax.ai team confirmed Flash as the right model for this.
  See [`CAPACITY.md`](CAPACITY.md).

## Changing it

- **Flags** are the `FLAGS` list at the top of `ctf.py`. Keep
  `docs/INCIDENTS.md` in step.
- **Agents** are plain kagent `Agent` manifests in `agents/`. The number
  prefix is only the order `make help` lists them in. `make agents-clear`
  removes them all.
- **Round lengths** are `ROUND_SECONDS` and `ROUND2_SECONDS`; run `make hub-07`
  after changing them.

## Afterwards

1. `/admin` → *Download emails* for the CSV of email, handle and score. It
   exists only on the hub.
2. `make hub-99` deletes the cluster, its volumes and its load balancer. It
   asks you to type the hub's name.
3. Check for leftovers: `civo firewall ls` and `civo volume ls` in the hub's
   region. Last time the cluster's firewall was left behind and had to be
   removed by hand.
4. Rotate the relax.ai key and the Civo key.
5. Delete `.state/`. It holds the admin key and tokens for a hub that no
   longer exists, and they get in the way of the next one: `hub-06` reuses a
   saved Grafana token if it finds one, and a new Grafana will refuse it.

## Where things are

| Path | What |
|------|------|
| `hub/step-*/` | Builds the hub. One `run.sh` each. |
| `hub/step-07-ctf/ctf.py` | The whole CTF app. |
| `hub/step-08-kagent/` | kagent's values and the guard. |
| `hub/step-10-slides/` | Builds the deck on the hub and serves it. |
| `slides/` | The deck's source. |
| `terraform/` | A cluster like the hub's, created and destroyed for one recording. |
| `agents/` | The three agents. |
| `examples/` | What the README gives attendees: kagent values and an agent scaffold. |
| `docs/RUNSHEET.md` | The plan for the session. |
| `docs/INCIDENTS.md` | The seeded dataset, its six incidents and the twelve flags. |
| `docs/CAPACITY.md` | Load measurements, and what is still unmeasured. |
| `docs/DEMO-PROMPTS.md` | Questions known to find each incident, and the model comparison. |
