import pathlib
import sys
sys.path.insert(0, str(pathlib.Path(__file__).parent))
from mkpptx import build

JOIN = "wall-74-220-17-251.sslip.io/join"
PASS = "kagent-sept-22"

S = []
def slide(**kw): S.append(kw)

# ─────────────────────────────────────────── ACT ONE — GETTING STARTED
slide(short="Title", title="Your Cluster Called\nand it's found a problem", big=True,
      eyebrow="kagent on Civo · 60 minutes",
      body=f"Get set up while you wait:   {JOIN}\nPassphrase:  {PASS}",
      notes="HOLDING SLIDE — up as people arrive, so early arrivals can start.\n"
            "Advance when you're ready to begin.")

slide(short="The hook", eyebrow="",
      title="“Checkout started returning 502s four days ago.\nIt lines up with a deploy.\n\n"
            "Something's exhausting the orders database\nconnection pool every night at 2am.\n\n"
            "Also — your auth certificate expires in nine days.”",
      sz=1600,
      body="Nobody told it to look for any of that.",
      notes="30 seconds. Read it, pause on the certificate line, then the payoff.\n\n"
            "Do NOT explain how yet. They're going to build the thing that said it,\n"
            "and the whole session works better if they get there themselves.")

slide(eyebrow="do this now", title="Get your credentials",
      mono=JOIN,
      body=f"Passphrase:  {PASS}\n\n"
           "Name, your Civo key, download the .env.\nYour Civo key never leaves your browser.",
      notes="LEAVE THIS REACHABLE ALL SESSION — people will ask twice.\n"
            "~3 minutes. Walk the room.\n\n"
            "Same name always returns the same credentials, so reloading is safe.\n"
            "No Civo account? dashboard.civo.com, free signup.\n\n"
            "Then get everyone to start their cluster before you talk.")

slide(eyebrow="what you're building", title="Two clusters, one protocol",
      body="YOURS                                    MINE\n"
           "  an agent that can reason        a platform you've never seen\n"
           "  and call tools                          seven days of its logs\n\n"
           "                     ── MCP ──▶",
      sz=1600,
      notes="Keep this light — 90 seconds. They'll see the detail live.\n\n"
            "The one point worth making: everything on the left is theirs and they\n"
            "keep it. The thing on the right is mine, and it's a platform that has\n"
            "been misbehaving for a week.\n\n"
            "LIVE: start step-01 here if you haven't. It returns immediately.")

# ─────────────────────────────────────────── ACT TWO — BACKGROUND
slide(eyebrow="background", title="An agent is a Kubernetes resource",
      body="ModelConfig          what it thinks with\n\n"
           "Agent                what it's for, and what it may touch\n\n"
           "RemoteMCPServer      where its tools come from\n\n"
           "kubectl get agents. Review it, diff it, roll it back.",
      notes="~3 min of air cover while clusters provision.\n\n"
            "The point: this isn't a chatbot bolted onto Kubernetes. It's a workload\n"
            "with an identity, RBAC and a manifest — the things you already know how\n"
            "to reason about.\n\n"
            "Good question for the room: who already runs something that reads logs\n"
            "at 3am? Right — same job, different implementation.")

slide(eyebrow="background", title="Why in the cluster at all?",
      body="It already has the credentials, the network reach, the RBAC.\n\n"
           "When it acts, it acts as an identity you granted —\n"
           "not a token someone pasted into a laptop.",
      notes="~2 min. This is the actual argument for the approach; make it properly.\n\n"
            "LIVE: by now step-02 and step-03 should be running. Show your own\n"
            "console — the ModelConfig is one baseUrl field pointing at relax.ai.\n"
            "Let someone read out what their agent said about their own cluster.")

slide(eyebrow="background", title="MCP: tools an agent can find for itself",
      body="Your agent has no idea what Loki is.\n\n"
           "It connects, asks what tools exist, and decides which to use.\n\n"
           "A driver, not an integration. You don't rebuild the agent\nto give it new senses.",
      notes="~2 min, immediately before they connect to the hub.\n\n"
            "This is the conceptual unlock. If they get this, step-04 lands.\n"
            "If you only make one point in the whole session, make this one.")

slide(short="Eight services, seven days", eyebrow="over to you",
      title="Eight services. Seven days.\nNobody has told it what's wrong.",
      body="web · api-gateway · checkout · orders-db-proxy\nsearch · image-resizer · notifications · auth\n\n"
           "Some of this is healthy. Some of it isn't.\n\nGo and find out which.",
      sz=1700,
      notes="THIS IS THE SESSION. Give it 12-15 minutes and get out of the way.\n\n"
            "Do NOT hand them questions. Let them interrogate it. Walk the room,\n"
            "read over shoulders, pull good findings up on the projector.\n\n"
            "There are six things genuinely in there — your answer key:\n"
            "  · checkout 502s stepping up after a v2.3.1 deploy, 4 days ago\n"
            "  · orders-db-proxy pool exhaustion, nightly 02:00-02:40\n"
            "  · image-resizer OOMKill loop, worsening over 2 days\n"
            "  · notifications = 45% of all log volume, debug left on\n"
            "  · auth TLS certificate expiring in 9 days, nothing failing yet\n"
            "  · search p99 creeping up ~8%/day with zero errors\n\n"
            "If the room stalls, nudge with a THEME not a prompt: 'has anything\n"
            "changed this week?' / 'anything on a schedule?' / 'anything about to\n"
            "break that hasn't yet?'\n\n"
            "Backstop, only if it's really flat — the verbatim prompt that finds\n"
            "the certificate: 'Is there anything that will fail in the next two\n"
            "weeks but is not failing today?'")

# ─────────────────────────────────────────── ACT THREE — CLOSING LEARNINGS
slide(eyebrow="closing", title="Now go and find it yourself",
      mono="logs-74-220-17-251.sslip.io",
      body="Same Loki. Same seven days. No agent.\n\n"
           "Anonymous, read-only — open it and try.",
      notes="DO THIS LIVE, and take your time fumbling. It is the strongest\n"
            "argument in the session and it makes itself.\n\n"
            "Open Explore, pick the Loki datasource, and try to find the auth\n"
            "certificate expiry. To get there you need to know: that Loki uses\n"
            "LogQL, that you want a label selector on service, that the line is\n"
            "at warn not error, and — the real problem — that certificates are\n"
            "a thing worth looking for at all.\n\n"
            "Everything the agent found is sitting right there. None of it is\n"
            "hidden. The difference is knowing what to ask.\n\n"
            "Let a couple of attendees try on the projector if they will.\n"
            "Nobody finds the certificate. That is the point -- it is the one\n"
            "incident where nothing is failing yet, so nothing draws your eye.\n\n"
            "Then move to the next slide and collect what they DID find with\n"
            "the agent.")

slide(eyebrow="closing", title="So what did you find?",
      body="",
      notes="COLLECT FROM THE ROOM. 5 minutes, and resist filling the silence.\n\n"
            "Ask who found something nobody else did. Ask if anyone's agent got\n"
            "something wrong. Both are useful.\n\n"
            "You're fishing for the three learnings on the next slides — if the room\n"
            "says them first, that's a better session than you saying them.")

slide(eyebrow="closing · learning", title="The question did the work",
      body="“Is anything about to break?”\n     → the crash loop. Everything else looks fine.\n\n"
           "“…but is not failing today?”\n     → the certificate, with nine days' notice.\n\n"
           "Same data. Same model.",
      sz=1600,
      notes="The most transferable thing in the session.\n\n"
            "The second phrasing makes it exclude what's already failing, so it has\n"
            "to reason about the future instead of ranking the present.\n\n"
            "If someone in the room discovered this themselves, credit them and let\n"
            "them explain it.")

slide(eyebrow="closing · learning", title="Check its work",
      body="In testing it once blamed the wrong service for a deploy —\n"
           "right finding, wrong attribution.\n\n"
           "It's a very fast colleague who has read everything\nand is sometimes confidently wrong.",
      notes="Be straight about this; it lands far better than pretending.\n\n"
            "The useful framing: this doesn't replace the on-call engineer, it gets\n"
            "them to the right three questions in thirty seconds instead of an hour.\n\n"
            "LIVE: show the wall here as the daily reports land.")

slide(eyebrow="closing · learning", title="It's just a workload",
      body="No console. No vendor. No agent platform.\n\n"
           "A Deployment, a Secret, a CronJob and a URL —\n"
           "reviewed, diffed and rolled back like anything else you run.",
      notes="The architectural takeaway, and the one that outlives the demo.\n\n"
            "Worth saying: swap relax.ai for a self-hosted model by editing one\n"
            "field. Swap Loki for whatever you already run, if it speaks MCP.")

slide(eyebrow="take these with you", title="Prompts worth stealing",
      body="What changed in the last 24 hours that wasn't happening last week?\n\n"
           "Anything failing on a schedule? Group by hour of day, not by count.\n\n"
           "Group today's errors by likely root cause, not by message.\n\n"
           "If I were paged right now, what would you check first — and why\n"
           "that rather than the others?\n\n"
           "Is anything degrading slowly enough that nobody has noticed?",
      sz=1500,
      notes="Point out these are SHAPES, not magic strings — their dataset is gone\n"
            "when the hub goes, but the question forms transfer.\n\n"
            "Two habits worth calling out:\n"
            "  · Ask for reasoning — 'and why that rather than the others' turns a\n"
            "    list into something you can argue with.\n"
            "  · Put your context in the system prompt, not the question. It doesn't\n"
            "    know which of your services matter or what normal looks like.\n\n"
            "All of these are in docs/AFTER.md so nobody has to photograph the slide.")

slide(eyebrow="take these with you", title="Where to take it next",
      body="Point log-detective at your own logs — one field on the RemoteMCPServer\n\n"
           "Rewrite the system prompt for your services — most of the quality is there\n\n"
           "Move it to a Monday digest — a daily nobody reads is worse than nothing\n\n"
           "Add a second MCP server: Prometheus, GitHub, PagerDuty\n\n"
           "Let it act, behind approval — start with something reversible\n\n"
           "Split it in two — you already have two; a triage agent routes to them",
      sz=1500,
      notes="In rough order of effort. The first one is where nearly all the value\n"
            "is and takes ten minutes — push it hardest.\n\n"
            "The second is the one people get wrong: they ship a daily report,\n"
            "nobody reads it by week two, and they conclude agents don't work.\n\n"
            "Third is where it stops being a log summariser and starts correlating\n"
            "— a deploy in GitHub against an error spike in Loki.\n\n"
            "examples/my-agent.yaml is a commented scaffold for all of this.")

slide(eyebrow="before you go", title="You're keeping this",
      body="It bills to YOUR Civo account.\n\n"
           "cluster-scout keeps working forever. log-detective loses its log\n"
           "tools when my hub goes on 22 October — repointing it at logs of\n"
           "your own is one field.\n\n"
           "Your relax.ai key is yours to keep.",
      notes="SAY THE BILLING LINE OUT LOUD. An unexpected charge next month is the\n"
            "one thing that turns a good workshop into a complaint.\n\n"
            "make clean deletes the cluster and its volumes.\n"
            "civo kubernetes scale <name> --nodes=1 halves it instead.\n\n"
            "On 22 October: only log-detective is affected, and the fix is one\n"
            "URL on the RemoteMCPServer pointed at their own Grafana. That is a\n"
            "better ending than running a copy of my fake platform — it sends\n"
            "them at their real systems. docs/AFTER.md has the command.\n\n"
            "Put 22 October in the follow-up email as well as on this slide.")

slide(eyebrow="thank you", title="Everything is in the repo",
      mono="github.com/dmajrekar/kagent-civo-workshop",
      body="Those prompts and next steps:  docs/AFTER.md\n\n"
           "kagent.dev  ·  civo.com  ·  relax.ai",
      notes="Leave up for Q&A.\n\n"
            "Likely questions: what does this cost to run for real; can it act as\n"
            "well as read (yes, with approval); does it work with self-hosted models\n"
            "(yes — one field); what if we don't run Loki (any MCP server works).")

BASE = str(pathlib.Path(__file__).parent)
build(S, f"{BASE}/Your Cluster Called - kagent workshop.pptx")


def markdown(slides):
    """Same slide list, rendered for a design tool rather than PowerPoint."""
    ACTS = {1: ("Act one", "Getting started"),
            5: ("Act two", "Background — air cover while clusters build"),
            9: ("Act three", "Closing — what they take away")}
    out = ["# Your Cluster Called",
           "",
           "*and it's found a problem*",
           "",
           "A 60-minute hands-on workshop: kagent on Civo, backed by relax.ai.",
           "",
           f"{len(slides)} slides. The machine needs about eight minutes of the hour — "
           "these slides are the air cover around it, so most are on screen for "
           "several minutes at a time.",
           "",
           "Speaker notes are the run of show: timings, what to say during the "
           "30–80 second agent waits, and the cut-lines.",
           ""]
    for i, sl in enumerate(slides, 1):
        if i in ACTS:
            act, desc = ACTS[i]
            out += ["---", "", f"# {act}", "", f"*{desc}*", ""]
        out += ["---", ""]
        title = sl.get("title", "").strip()
        flat = " ".join(title.split())
        # A slide's display text is not always a usable heading -- the hook
        # is a three-line quote. Those carry a short heading and show the
        # real text as content underneath.
        heading = sl.get("short") or (flat if len(flat) <= 60 else flat[:57] + "…")
        out.append(f"## {i}. {heading}")
        out.append("")
        if sl.get("eyebrow"):
            out += [f"**Label:** {sl['eyebrow']}", ""]
        if sl.get("short"):
            out.append("### Headline")
            out.append("")
            out += ["> " + l if l.strip() else ">" for l in title.split("\n")]
            out.append("")
        if sl.get("mono"):
            out += ["```", sl["mono"], "```", ""]
        if sl.get("big"):
            out += ["*Title slide — set this large.*", ""]
        body = (sl.get("body") or "").strip()
        if body:
            out.append("### On the slide")
            out.append("")
            # Body lines are laid out visually, so keep them as a block.
            out += ["```text", body, "```", ""]
        notes = (sl.get("notes") or "").strip()
        if notes:
            out.append("### Speaker notes")
            out.append("")
            out += ["> " + ln if ln.strip() else ">" for ln in notes.split("\n")]
            out.append("")
    return "\n".join(out).rstrip() + "\n"


md = f"{BASE}/your-cluster-called-deck.md"
pathlib.Path(md).write_text(markdown(S))
print(f"{len(S)} slides -> pptx + markdown ({len(markdown(S).splitlines())} lines)")
