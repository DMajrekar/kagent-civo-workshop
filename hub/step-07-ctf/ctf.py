#!/usr/bin/env python3
"""The CTF: join page, flag checker, scoreboard, round control, kagent gateway.

One small server, standard library only, built for a room on mobile data:

  /            join with an email, then your flag sheet
  /board       the projector scoreboard
  /admin       the instructor's round control
  /gw/*        identity and round-lock decisions for the kagent ingress

The game is two timed rounds against the same flags. Round one, the room has
Grafana. Round two, the instructor unlocks kagent and the room carries on from
wherever Grafana left them. Every solve records which round it landed in, so
the scoreboard can show the difference rather than have you assert it.

Pages poll rather than hold a stream open: a phone on a congested cell drops
long-lived connections constantly, and a five-second poll just works.

Everything rendered from a player is escaped or set with textContent. Handles
are generated, never typed, so nothing a player controls reaches the projector.
"""
import hashlib, hmac, html, json, os, re, secrets, threading, time
import urllib.parse, urllib.request
from collections import defaultdict, deque
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

DATA_PATH = os.environ.get("DATA_PATH", "/data/ctf.json")
SECRET = os.environ.get("CTF_SECRET", "").encode()
ADMIN_KEY = os.environ.get("ADMIN_KEY", "").strip()
PUBLIC_URL = os.environ.get("PUBLIC_URL", "").strip().rstrip("/")
GRAFANA_URL = os.environ.get("GRAFANA_URL", "").strip()
KAGENT_URL = os.environ.get("KAGENT_URL", "").strip().rstrip("/")
KAGENT_API = os.environ.get("KAGENT_API", "").strip().rstrip("/")
KAGENT_NS = os.environ.get("KAGENT_NAMESPACE", "kagent")
ROUND_SECONDS = int(os.environ.get("ROUND_SECONDS", "600"))
# Round two is shorter: asking is quicker than typing queries.
ROUND2_SECONDS = int(os.environ.get("ROUND2_SECONDS", "900"))
PHASE_SECONDS = {"grafana": ROUND_SECONDS, "kagent": ROUND2_SECONDS}
JOIN_NOTICE = os.environ.get(
    "JOIN_NOTICE", "Your email identifies you in this session. "
                   "The scoreboard shows a generated handle, never your email.")
TITLE = os.environ.get("CTF_TITLE", "Your cluster called")

# Mobile carriers put hundreds of phones behind one address, so per-IP limits
# here are loose: they are a brake on a script, not on a room.
JOIN_PER_MIN = 120
SUBMIT_PER_MIN = 12            # per player; the hour flag has only 24 answers

EMAIL_RE = re.compile(r"^[^@\s]{1,64}@[^@\s]{1,190}\.[^@\s.]{2,24}$")
COOKIE = "ctf"                 # on the CTF host
GW_COOKIE = "ctfk"             # on the kagent host
# What a player may load from the kagent host: a chat with an agent in our
# namespace, and what that page fetches. Checked in _gw_auth.
GW_ALLOWED = re.compile(
    r"^/(?:(?:api|a2a|_next)/.*"
    r"|agents/" + re.escape(KAGENT_NS) + r"/[^/]+/chat(?:/[^/]+)?/?"
    r"|icon|favicon\.ico)$")

ADJECTIVES = ["amber","brisk","calm","coral","dusky","eager","fleet","golden",
              "hazel","ivory","jade","keen","lunar","misty","noble","olive",
              "prism","quiet","rapid","sable","tidal","umber","vivid","warm"]
NOUNS = ["otter","falcon","cedar","harbor","lantern","meadow","nimbus","onyx",
         "pebble","quarry","ridge","summit","thicket","vessel","willow","yarrow",
         "anvil","beacon","cobalt","delta","ember","fjord","grove","hollow"]

# ---------------------------------------------------------------------- flags
#
# Every answer is a fact about the seeded dataset (docs/INCIDENTS.md) that does
# not move when the dataset is re-seeded: names, versions, hours of the day.
# Nothing here depends on what date the backfill ran.
#
# `accept` patterns are matched against the whole answer after it has been
# lower-cased and stripped of quotes and trailing punctuation.
FLAGS = [
    dict(id="volume", pts=100, title="The loudest voice",
         q="One service writes most of the log lines on this platform. Which one?",
         fmt="service name", accept=[r"notifications?"]),
    dict(id="level", pts=100, title="…and what it is shouting",
         q="At which log level is that service flooding?",
         fmt="a log level", accept=[r"debug"]),
    dict(id="regressed", pts=100, title="Something got worse",
         q="One service's error count jumped part-way through the week and never came back down. Which?",
         fmt="service name", accept=[r"checkout"]),
    dict(id="version", pts=150, title="Blame the deploy",
         q="Which version was running when that started?",
         fmt="vX.Y.Z", accept=[r"v?2\.3\.1"]),
    dict(id="build", pts=150, title="Build number",
         q="That version logged a build number when it first started. What is it?",
         fmt="a number", accept=[r"(build\s*)?#?8812"]),
    dict(id="oom", pts=100, title="Crashloop",
         q="Which service keeps being killed for running out of memory?",
         fmt="service name", accept=[r"image-?\s?resizer"]),
    dict(id="exit", pts=150, title="Exit code",
         q="What exit code does it log each time it is killed?",
         fmt="a number", accept=[r"(exit\s*(code)?\s*)?137"]),
    dict(id="nightly", pts=150, title="Clockwork",
         q="One service fails at the same time every night. Which?",
         fmt="service name", accept=[r"orders-?\s?db-?\s?proxy"]),
    dict(id="hour", pts=150, title="What time?",
         q="At what hour (UTC) does that nightly failure start?",
         fmt="hour, 0-23",
         accept=[r"0?2([:.h]00)?\s*(am|a\.m\.)?\s*(utc|gmt|z)?", r"two"]),
    dict(id="job", pts=200, title="The culprit",
         q="A scheduled job starts at exactly that moment. What is it called?",
         fmt="job name", accept=[r"(job=)?orders-?\s?reconciles?"]),
    dict(id="slow", pts=250, title="Slow burn",
         q="One service is getting slower every day and has not logged a single error. Which?",
         fmt="service name", accept=[r"search"]),
    dict(id="cert", pts=300, title="Not broken yet",
         q="Nothing is failing here, but something will within two weeks. "
           "Which hostname's certificate is about to expire?",
         fmt="hostname", accept=[r"auth\.internal"]),
]
FLAG_BY_ID = {f["id"]: f for f in FLAGS}
for _f in FLAGS:
    _f["_re"] = [re.compile(p) for p in _f["accept"]]
MAX_POINTS = sum(f["pts"] for f in FLAGS)

PHASES = ("lobby", "grafana", "kagent", "done")
ROUND_OF = {"grafana": 1, "kagent": 2}


def now_ms():
    return int(time.time() * 1000)


def normalise_answer(s):
    s = " ".join(str(s).lower().split())
    return s.strip(" \t\"'`.,;:!?()[]{}")


def check_flag(flag, answer):
    a = normalise_answer(answer)
    return bool(a) and any(r.fullmatch(a) for r in flag["_re"])


# ---------------------------------------------------------------------- state
#
# All of it is one small JSON document: players, solves, and where the round
# is. It is written atomically on every change so a pod restart mid-session
# loses nothing -- a scoreboard that resets itself halfway through round two
# would end the exercise.
LOCK = threading.RLock()
STATE = {"players": {}, "solves": {}, "next": 0,
         "phase": "lobby", "started": 0, "ends": 0, "rounds": {}}
BY_EMAIL = {}
HITS = defaultdict(deque)


def load_state():
    try:
        with open(DATA_PATH) as fh:
            STATE.update(json.load(fh))
    except FileNotFoundError:
        pass
    except Exception as e:                       # never start on a corrupt file silently
        print(f"WARNING: could not read {DATA_PATH}: {e}", flush=True)
    BY_EMAIL.clear()
    BY_EMAIL.update({p["email"]: pid for pid, p in STATE["players"].items()})


def save_state():
    tmp = DATA_PATH + ".tmp"
    os.makedirs(os.path.dirname(DATA_PATH) or ".", exist_ok=True)
    with open(tmp, "w") as fh:
        json.dump(STATE, fh)
        fh.flush()
        os.fsync(fh.fileno())
    os.replace(tmp, DATA_PATH)


def rate_ok(key, per_min):
    with LOCK:
        q = HITS[key]
        cutoff = time.time() - 60
        while q and q[0] < cutoff:
            q.popleft()
        if len(q) >= per_min:
            return False
        q.append(time.time())
        return True


# ------------------------------------------------------------------- identity

def _sig(msg):
    return hmac.new(SECRET, msg.encode(), hashlib.sha256).hexdigest()[:32]


def session_token(pid):
    return f"{pid}.{_sig('s|' + pid)}"


def read_session(tok):
    pid, _, sig = (tok or "").partition(".")
    if pid and hmac.compare_digest(sig, _sig("s|" + pid)):
        with LOCK:
            return pid if pid in STATE["players"] else None
    return None


def entry_token(pid, ttl=120):
    """Short-lived, single-purpose: carries a player across to the kagent host."""
    exp = str(int(time.time()) + ttl)
    return f"{pid}.{exp}.{_sig('e|' + pid + '|' + exp)}"


def read_entry(tok):
    parts = (tok or "").split(".")
    if len(parts) != 3:
        return None
    pid, exp, sig = parts
    if not hmac.compare_digest(sig, _sig("e|" + pid + "|" + exp)):
        return None
    if not exp.isdigit() or int(exp) < time.time():
        return None
    with LOCK:
        return pid if pid in STATE["players"] else None


def join(email):
    email = str(email).strip().lower()
    if not EMAIL_RE.match(email):
        return None, "that does not look like an email address"
    with LOCK:
        pid = BY_EMAIL.get(email)
        if pid:                                   # same email, same player
            return pid, None
        idx = STATE["next"]
        pid = secrets.token_hex(6)
        handle = (f"{ADJECTIVES[idx % len(ADJECTIVES)]}-"
                  f"{NOUNS[(idx * 7 + 3) % len(NOUNS)]}-{idx + 1:02d}")
        STATE["players"][pid] = {"email": email, "handle": handle, "joined": now_ms()}
        STATE["next"] = idx + 1
        BY_EMAIL[email] = pid
        save_state()
        return pid, None


# ---------------------------------------------------------------------- rounds

def round_view():
    """What the clock says right now. `open` is whether answers are accepted."""
    with LOCK:
        phase, ends = STATE["phase"], STATE["ends"]
        left = max(0, ends - now_ms()) if phase in ROUND_OF else 0
        return {"phase": phase, "round": ROUND_OF.get(phase, 0),
                "ends": ends, "left_ms": left,
                "open": phase in ROUND_OF and left > 0,
                "kagent": phase in ("kagent", "done"),
                "seconds": PHASE_SECONDS.get(phase, ROUND_SECONDS)}


def admin_action(action):
    with LOCK:
        t = now_ms()
        if action != "add_minute":
            # Whatever was running stops now: a round cut short must not be
            # credited with its full length on the scoreboard.
            for info in STATE["rounds"].values():
                info["ends"] = min(info["ends"], t)
        if action in ("start_grafana", "start_kagent"):
            phase = "grafana" if action == "start_grafana" else "kagent"
            STATE["phase"], STATE["started"] = phase, t
            STATE["ends"] = t + PHASE_SECONDS[phase] * 1000
            STATE["rounds"][str(ROUND_OF[phase])] = {"started": t, "ends": STATE["ends"]}
        elif action == "add_minute":
            if STATE["phase"] not in ROUND_OF:
                return "no round is running"
            STATE["ends"] = max(STATE["ends"], t) + 60000
            STATE["rounds"][str(ROUND_OF[STATE["phase"]])]["ends"] = STATE["ends"]
        elif action == "finish":
            STATE["phase"], STATE["ends"] = "done", t
        elif action == "lobby":
            STATE["phase"], STATE["started"], STATE["ends"] = "lobby", 0, 0
        elif action == "reset_scores":
            STATE["solves"], STATE["rounds"] = {}, {}
            STATE["phase"], STATE["started"], STATE["ends"] = "lobby", 0, 0
        else:
            return "unknown action"
        save_state()
        return None


def submit(pid, flag_id, answer):
    flag = FLAG_BY_ID.get(flag_id)
    if not flag:
        return 404, {"error": "no such flag"}
    rv = round_view()
    if not rv["open"]:
        return 409, {"error": "the round is not running — answers are closed"}
    with LOCK:
        mine = STATE["solves"].setdefault(pid, {})
        if flag_id in mine:
            return 200, {"correct": True, "already": True}
    if not rate_ok("sub|" + pid, SUBMIT_PER_MIN):
        return 429, {"error": "slow down — a few guesses a minute is plenty"}
    if not check_flag(flag, answer):
        return 200, {"correct": False}
    with LOCK:
        mine = STATE["solves"].setdefault(pid, {})
        mine.setdefault(flag_id, {"at": now_ms(), "round": rv["round"]})
        save_state()
    return 200, {"correct": True, "points": flag["pts"]}


def score(pid):
    with LOCK:
        return sum(FLAG_BY_ID[f]["pts"] for f in STATE["solves"].get(pid, {})
                   if f in FLAG_BY_ID)


def board():
    with LOCK:
        rows = []
        for pid, p in STATE["players"].items():
            mine = STATE["solves"].get(pid, {})
            last = max((s["at"] for s in mine.values()), default=0)
            rows.append({"handle": p["handle"],
                         "score": sum(FLAG_BY_ID[f]["pts"] for f in mine if f in FLAG_BY_ID),
                         "last": last,
                         "solves": {f: s["round"] for f, s in mine.items() if f in FLAG_BY_ID}})
        # Highest score first; ties go to whoever got there sooner.
        rows.sort(key=lambda r: (-r["score"], r["last"] or 1 << 62, r["handle"]))
        per_round = {}
        for rnd in ("1", "2"):
            info = STATE["rounds"].get(rnd)
            n = sum(1 for m in STATE["solves"].values()
                    for s in m.values() if str(s["round"]) == rnd)
            mins = 0.0
            if info:
                mins = (min(now_ms(), info["ends"]) - info["started"]) / 60000.0
            per_round[rnd] = {"solves": n, "minutes": round(max(mins, 0), 2),
                              "ran": bool(info)}
        return {"round": round_view(), "players": len(rows), "rows": rows,
                "flags": [{"id": f["id"], "title": f["title"], "pts": f["pts"]} for f in FLAGS],
                "rounds": per_round, "max": MAX_POINTS}


# --------------------------------------------------------------------- agents
#
# The instructor adds agents with kubectl during the talk. Ask kagent what
# exists rather than keeping a list here, so a new agent shows up on every
# phone a few seconds after it becomes ready, with nothing to redeploy.
_AGENTS = {"at": 0.0, "items": []}


def agents():
    if not KAGENT_API:
        return []
    with LOCK:
        if time.time() - _AGENTS["at"] < 5:
            return _AGENTS["items"]
        _AGENTS["at"] = time.time()            # claim the refresh; others reuse stale
    out = []
    try:
        req = urllib.request.Request(KAGENT_API + "/agents",
                                     headers={"Accept": "application/json",
                                              "X-User-Id": "ctf-gateway"})
        with urllib.request.urlopen(req, timeout=4) as r:
            data = json.load(r).get("data") or []
        for a in data:
            res = a.get("agent") or {}
            meta = res.get("metadata") or {}
            name, ns = meta.get("name"), meta.get("namespace", KAGENT_NS)
            if not name or ns != KAGENT_NS:
                continue
            out.append({"name": name, "ns": ns,
                        "desc": ((res.get("spec") or {}).get("description") or "")[:200],
                        "ready": bool(a.get("deploymentReady")) and bool(a.get("accepted", True))})
        out.sort(key=lambda a: a["name"])
    except Exception as e:
        print(f"agents: could not list from kagent: {type(e).__name__}: {e}", flush=True)
        with LOCK:
            return _AGENTS["items"]
    with LOCK:
        _AGENTS["items"] = out
    return out


# Starting points for round one, opened in Explore ready to run. Without them
# a player on a phone has to already know LogQL's metric syntax to get past a
# wall of raw lines. They show shapes of question, not answers: nothing here
# mentions a latency, a certificate or a deploy.
STARTERS = [
    ("Lines per service, per hour", 'sum by (service) (count_over_time({env="production"}[1h]))'),
    ("Errors per service, per hour", 'sum by (service) (count_over_time({level="error"}[1h]))'),
    ("Lines per level, per hour", 'sum by (level) (count_over_time({env="production"}[1h]))'),
    ("One service, errors only", '{service="web", level="error"}'),
    ("Search every line for a word", '{env="production"} |= "timeout"'),
]


def explore_url(expr):
    """GRAFANA_URL with its query swapped for `expr`."""
    try:
        u = urllib.parse.urlsplit(GRAFANA_URL)
        q = dict(urllib.parse.parse_qsl(u.query))
        panes = json.loads(q["panes"])
        for pane in panes.values():
            for query in pane["queries"]:
                query["expr"] = expr
        q["panes"] = json.dumps(panes)
        return urllib.parse.urlunsplit(u._replace(query=urllib.parse.urlencode(q)))
    except (KeyError, ValueError, TypeError):
        return ""


STARTER_LINKS = [{"k": k, "q": expr, "url": explore_url(expr)} for k, expr in STARTERS]
STARTER_LINKS = [x for x in STARTER_LINKS if x["url"]]


def me(pid):
    with LOCK:
        p = STATE["players"][pid]
        mine = dict(STATE["solves"].get(pid, {}))
    rv = round_view()
    hidden = rv["phase"] == "lobby"
    flags = [{"id": f["id"], "title": f["title"], "pts": f["pts"],
              "q": "" if hidden else f["q"], "fmt": f["fmt"],
              "solved": f["id"] in mine,
              "round": mine.get(f["id"], {}).get("round", 0)} for f in FLAGS]
    return {"handle": p["handle"], "score": score(pid), "max": MAX_POINTS,
            "round": rv, "flags": flags,
            "grafana": GRAFANA_URL if rv["phase"] != "lobby" else "",
            "starters": STARTER_LINKS if rv["phase"] != "lobby" else [],
            "agents": agents() if rv["kagent"] else []}


# ---------------------------------------------------------------------- pages

STYLE = """
:root{--bg:#fbfaf8;--fg:#1a1a19;--dim:#6b6a67;--line:#e2e0dc;--card:#fff;
      --accent:#b4530a;--r1:#2f6fb3;--r2:#b4530a;--ok:#2e7d4f;--bad:#b3261e}
@media(prefers-color-scheme:dark){:root{--bg:#171715;--fg:#ece9e4;--dim:#9a9791;
      --line:#2f2e2b;--card:#1f1f1d;--accent:#e08b4c;--r1:#6ea8e0;--r2:#e08b4c;
      --ok:#6cc08b;--bad:#f2857d}}
/* /board?embed, framed inside the slide deck: always dark, on the deck's black. */
:root.embed{--bg:#000;--fg:#ece9e4;--dim:#9a9791;
      --line:#2f2e2b;--card:#141413;--accent:#e08b4c;--r1:#6ea8e0;--r2:#ff7633;
      --ok:#6cc08b;--bad:#f2857d}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--fg);
     font:16px/1.5 ui-sans-serif,system-ui,-apple-system,"Segoe UI",sans-serif}
.wrap{max-width:760px;margin:0 auto;padding:20px 16px 64px}
h1{font-size:1.4rem;margin:0 0 4px;letter-spacing:-.02em}
h2{font-size:1rem;margin:26px 0 10px}
.sub{color:var(--dim);margin:0 0 20px}
a{color:var(--accent)}
code,pre{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:.85em}
input,button{font:inherit}
input[type=email],input[type=text],input[type=password]{width:100%;padding:11px 12px;
     border:1px solid var(--line);border-radius:8px;background:var(--card);color:var(--fg)}
button{padding:11px 16px;border-radius:8px;border:1px solid var(--line);
     background:var(--card);color:var(--fg);cursor:pointer}
button.go{background:var(--accent);border-color:var(--accent);color:#fff;font-weight:600}
button:disabled{opacity:.5;cursor:default}
.card{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:14px 16px;margin:10px 0}
.bar{display:flex;gap:12px;align-items:center;flex-wrap:wrap;position:sticky;top:0;
     background:var(--bg);padding:10px 0;border-bottom:1px solid var(--line);z-index:2}
.bar .who{font-weight:600}
.bar .pts{margin-left:auto;font-variant-numeric:tabular-nums;font-weight:600}
.pill{font-size:.78rem;padding:3px 9px;border-radius:99px;border:1px solid var(--line);color:var(--dim)}
.pill.r1{color:var(--r1);border-color:var(--r1)} .pill.r2{color:var(--r2);border-color:var(--r2)}
.clock{font-variant-numeric:tabular-nums;font-weight:600}
.tool{display:block;text-decoration:none;color:inherit}
.tool .k{font-weight:600;display:block} .tool .d{color:var(--dim);font-size:.88rem;display:block}
.tool.off{opacity:.55}
.starters{margin:-4px 0 10px;padding:0 4px}
.starters summary{color:var(--dim);font-size:.88rem;cursor:pointer;padding:6px 0}
.starters a{display:block;text-decoration:none;color:inherit;border-top:1px solid var(--line);padding:9px 0}
.starters .k{display:block;font-weight:600;font-size:.92rem}
.starters code{display:block;color:var(--dim);font-size:.74rem;overflow-wrap:anywhere}
.flag .top{display:flex;gap:10px;align-items:baseline}
.flag .t{font-weight:600} .flag .p{margin-left:auto;color:var(--dim);font-size:.85rem;white-space:nowrap}
.flag .q{margin:6px 0 10px;color:var(--fg)}
.flag form{display:flex;gap:8px} .flag form input{flex:1;min-width:0}
.flag.done{border-color:var(--ok)} .flag.done .t::before{content:"✓ ";color:var(--ok)}
.msg{font-size:.85rem;margin-top:6px;min-height:1.2em} .msg.bad{color:var(--bad)} .msg.ok{color:var(--ok)}
details{margin:10px 0} summary{cursor:pointer;color:var(--dim)}
pre{background:var(--card);border:1px solid var(--line);border-radius:8px;padding:10px;overflow:auto;white-space:pre-wrap}
.dim{color:var(--dim)} .err{color:var(--bad)}
"""


def page(title, body, wide=False):
    cls = "wrap wide" if wide else "wrap"
    return f"""<!doctype html><html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>{html.escape(title)}</title><style>{STYLE}</style></head>
<body><div class="{cls}">{body}</div></body></html>"""


def join_page():
    return page(TITLE, f"""
<h1>{html.escape(TITLE)}</h1>
<p class="sub">A capture-the-flag in a week of production logs. First with
Grafana, then with an agent.</p>
<form id="f" class="card">
  <label for="email"><b>Your email</b></label>
  <p class="dim" style="margin:4px 0 10px;font-size:.88rem">{html.escape(JOIN_NOTICE)}</p>
  <input id="email" type="email" inputmode="email" autocomplete="email"
         autocapitalize="off" required placeholder="you@example.com">
  <p style="margin:12px 0 0"><button class="go" type="submit">Join</button></p>
  <p id="err" class="msg bad"></p>
</form>
<script>
document.getElementById("f").onsubmit=async e=>{{
  e.preventDefault();
  const err=document.getElementById("err"); err.textContent="";
  try{{
    const r=await fetch("/api/join",{{method:"POST",headers:{{"Content-Type":"application/json"}},
      body:JSON.stringify({{email:document.getElementById("email").value}})}});
    const d=await r.json();
    if(!r.ok){{err.textContent=d.error||"could not join";return;}}
    location.reload();
  }}catch(x){{err.textContent="no connection — try again";}}
}};
</script>""")


PLAY = page(TITLE, """
<div class="bar">
  <span class="who" id="who"></span>
  <span class="pill" id="phase"></span>
  <span class="clock" id="clock"></span>
  <span class="pts" id="pts"></span>
</div>
<p id="conn" class="msg bad"></p>

<h2>Your tools</h2>
<div id="tools"></div>

<details id="cheat" hidden>
  <summary>LogQL in sixty seconds</summary>
<pre>{service="checkout"}                 every line from one service
{service="auth", level="warn"}       narrow by level
{env="production"} |= "timeout"      lines containing some text

sum by (service) (count_over_time({env="production"}[1h]))
                                     how many lines, per service
sum by (level) (count_over_time({service="checkout"}[1h]))
                                     …or per level, for one service

Labels you can use: service, level, env, version.
Set the time range (top right) to "Last 7 days".</pre>
</details>

<h2>Flags</h2>
<p class="dim" id="lobby" hidden>The flags appear when the first round starts.
Keep this page open.</p>
<div id="flags"></div>

<script>
const $=id=>document.getElementById(id);
let S=null, skew=0, built=false, starterOpen=true;
const NAMES={lobby:"Waiting to start",grafana:"Round 1 · Grafana",kagent:"Round 2 · kagent",done:"Finished"};

function el(tag,cls,text){const e=document.createElement(tag);if(cls)e.className=cls;if(text!=null)e.textContent=text;return e;}

function tool(href,k,d,off){
  const a=el(href&&!off?"a":"div","card tool"+(off?" off":""));
  if(href&&!off){a.href=href;a.target="_blank";a.rel="noopener";}
  a.append(el("span","k",k),el("span","d",d)); return a;
}

function renderTools(){
  const t=$("tools"); t.replaceChildren();
  const ph=S.round.phase;
  if(ph==="lobby"){t.append(tool(null,"Nothing yet","Your tools unlock when the round starts.",true));return;}
  t.append(tool(S.grafana,"Grafana Explore","Seven days of logs from eight services. Query them with LogQL."));
  if((S.starters||[]).length){
    const d=el("details","starters"); d.open=starterOpen;
    d.addEventListener("toggle",()=>{starterOpen=d.open;});
    d.append(el("summary",null,"Starter queries — tap one to open it in Grafana"));
    for(const q of S.starters){
      const a=el("a"); a.href=q.url; a.target="_blank"; a.rel="noopener";
      a.append(el("span","k",q.k),el("code",null,q.q)); d.append(a);
    }
    t.append(d);
  }
  if(!S.round.kagent){t.append(tool(null,"kagent","Locked until round 2.",true));return;}
  if(!S.agents.length){t.append(tool(null,"kagent","Unlocked — the first agent is on its way.",true));return;}
  for(const a of S.agents){
    const to="/agents/"+encodeURIComponent(a.ns)+"/"+encodeURIComponent(a.name)+"/chat";
    t.append(tool(a.ready?"/go/kagent?to="+encodeURIComponent(to):null,
      "Agent · "+a.name, a.ready?(a.desc||"Ask it about the logs."):"Starting up…", !a.ready));
  }
}

function buildFlags(){
  const box=$("flags"); box.replaceChildren();
  for(const f of S.flags){
    const c=el("div","card flag"); c.id="flag-"+f.id;
    const top=el("div","top"); top.append(el("span","t",f.title),el("span","p",f.pts+" pts"));
    const q=el("p","q",f.q);
    const form=el("form"); const inp=el("input"); inp.type="text"; inp.placeholder=f.fmt;
    inp.autocapitalize="off"; inp.autocomplete="off"; inp.spellcheck=false;
    const b=el("button","go","Submit"); b.type="submit";
    const msg=el("p","msg");
    form.append(inp,b);
    form.onsubmit=async e=>{
      e.preventDefault(); if(!inp.value.trim())return;
      b.disabled=true; msg.className="msg"; msg.textContent="";
      try{
        const r=await fetch("/api/submit",{method:"POST",headers:{"Content-Type":"application/json"},
          body:JSON.stringify({flag:f.id,answer:inp.value})});
        const d=await r.json();
        if(!r.ok){msg.className="msg bad";msg.textContent=d.error||"not accepted";}
        else if(d.correct){await poll();}
        else{msg.className="msg bad";msg.textContent="Not that. Try again.";}
      }catch(x){msg.className="msg bad";msg.textContent="no connection — try again";}
      b.disabled=false;
    };
    c.append(top,q,form,msg); box.append(c);
  }
  built=true;
}

function renderFlags(){
  const hidden=S.round.phase==="lobby";
  $("lobby").hidden=!hidden; $("flags").hidden=hidden;
  if(hidden){built=false;return;}
  if(!built)buildFlags();
  for(const f of S.flags){
    const c=$("flag-"+f.id); if(!c)continue;
    const form=c.querySelector("form"), msg=c.querySelector(".msg");
    if(f.solved){
      c.classList.add("done"); form.hidden=true;
      msg.className="msg ok"; msg.textContent="Solved in round "+f.round+" · +"+f.pts;
    }else{
      c.classList.remove("done"); form.hidden=false;
      form.querySelector("button").disabled=!S.round.open;
      form.querySelector("input").disabled=!S.round.open;
    }
  }
}

function tick(){
  if(!S)return;
  const r=S.round, c=$("clock");
  if(r.round){
    const left=Math.max(0,r.ends-(Date.now()+skew));
    const m=Math.floor(left/60000), s=Math.floor(left%60000/1000);
    c.textContent=left>0?(m+":"+String(s).padStart(2,"0")):"time!";
    if(left<=0&&r.open){r.open=false;renderFlags();}
  }else c.textContent="";
}

function render(){
  $("who").textContent=S.handle;
  $("pts").textContent=S.score+" / "+S.max;
  const p=$("phase"); p.textContent=NAMES[S.round.phase]||S.round.phase;
  p.className="pill"+(S.round.round?" r"+S.round.round:"");
  $("cheat").hidden=S.round.phase==="lobby";
  renderTools(); renderFlags(); tick();
}

async function poll(){
  try{
    const r=await fetch("/api/me",{cache:"no-store"});
    if(r.status===401){location.reload();return;}
    const d=await r.json();
    // Phones have wrong clocks. Count down against the server's, not ours.
    skew=(d.now||Date.now())-Date.now();
    S=d; $("conn").textContent=""; render();
  }catch(x){$("conn").textContent="Connection lost — retrying…";}
}
poll(); setInterval(poll,5000); setInterval(tick,500);
document.addEventListener("visibilitychange",()=>{if(!document.hidden)poll();});
</script>""")


BOARD = page("Scoreboard", """
<style>
.wide{max-width:1200px}
.head{display:flex;gap:18px;align-items:baseline;flex-wrap:wrap}
.head h1{font-size:1.8rem} .head .clock{font-size:1.8rem;margin-left:auto}
.cmp{display:grid;grid-template-columns:1fr 1fr;gap:12px;margin:14px 0 6px}
.cmp .card{margin:0} .cmp .n{font-size:2.4rem;font-weight:700;line-height:1.1;font-variant-numeric:tabular-nums}
.cmp .r1 .n{color:var(--r1)} .cmp .r2 .n{color:var(--r2)}
table{width:100%;border-collapse:collapse;margin-top:10px}
th,td{text-align:left;padding:7px 8px;border-bottom:1px solid var(--line);white-space:nowrap}
th{color:var(--dim);font-weight:500;font-size:.8rem}
td.s{font-weight:700;font-variant-numeric:tabular-nums;text-align:right}
td.n{color:var(--dim);text-align:right;width:2em}
.dots{display:flex;gap:4px}
.dot{width:14px;height:14px;border-radius:4px;border:1px solid var(--line)}
.dot.r1{background:var(--r1);border-color:var(--r1)} .dot.r2{background:var(--r2);border-color:var(--r2)}
.key{color:var(--dim);font-size:.85rem;display:flex;gap:16px;align-items:center;margin-top:8px}
.key .dot{display:inline-block;vertical-align:-2px;margin-right:5px}
</style>
<div class="head"><h1 id="phase"></h1><span class="dim" id="count"></span><span class="clock" id="clock"></span></div>
<div class="cmp">
  <div class="card r1"><div class="dim">Round 1 · Grafana</div><div class="n" id="r1">–</div><div class="dim" id="r1d"></div></div>
  <div class="card r2"><div class="dim">Round 2 · kagent</div><div class="n" id="r2">–</div><div class="dim" id="r2d"></div></div>
</div>
<div class="key"><span><span class="dot r1"></span>solved with Grafana</span>
<span><span class="dot r2"></span>solved with kagent</span><span id="conn" class="err"></span></div>
<table><thead><tr><th></th><th>Player</th><th>Flags, easiest to hardest</th><th style="text-align:right">Score</th></tr></thead>
<tbody id="rows"></tbody></table>
<script>
if(new URLSearchParams(location.search).has("embed"))document.documentElement.classList.add("embed");
const $=id=>document.getElementById(id);
let B=null, skew=0;
const NAMES={lobby:"Waiting to start",grafana:"Round 1 · Grafana",kagent:"Round 2 · kagent",done:"Final scores"};
function el(tag,cls,text){const e=document.createElement(tag);if(cls)e.className=cls;if(text!=null)e.textContent=text;return e;}
function rnd(k,n,d){
  const r=B.rounds[k];
  if(!r.ran){$(n).textContent="–";$(d).textContent="";return;}
  $(n).textContent=r.solves+" flags";
  const per=B.players?(r.solves/B.players):0;
  $(d).textContent=per.toFixed(1)+" per player in "+Math.max(1,Math.round(r.minutes))+" min";
}
function tick(){
  if(!B)return; const r=B.round;
  if(!r.round){$("clock").textContent="";return;}
  const left=Math.max(0,r.ends-(Date.now()+skew));
  $("clock").textContent=left>0?(Math.floor(left/60000)+":"+String(Math.floor(left%60000/1000)).padStart(2,"0")):"time!";
}
function render(){
  $("phase").textContent=NAMES[B.round.phase]||B.round.phase;
  $("count").textContent=B.players+" playing";
  rnd("1","r1","r1d"); rnd("2","r2","r2d");
  const tb=$("rows"); tb.replaceChildren();
  B.rows.forEach((p,i)=>{
    const tr=el("tr"); tr.append(el("td","n",String(i+1)),el("td",null,p.handle));
    const td=el("td"), dots=el("div","dots");
    for(const f of B.flags){const d=el("span","dot"+(p.solves[f.id]?" r"+p.solves[f.id]:""));d.title=f.title;dots.append(d);}
    td.append(dots); tr.append(td,el("td","s",String(p.score))); tb.append(tr);
  });
  tick();
}
async function poll(){
  try{const r=await fetch("/api/board",{cache:"no-store"});const d=await r.json();
      skew=(d.now||Date.now())-Date.now();B=d;$("conn").textContent="";render();}
  catch(x){$("conn").textContent="connection lost — retrying";}
}
poll(); setInterval(poll,4000); setInterval(tick,500);
</script>""", wide=True)


ADMIN = page("Round control", """
<h1>Round control</h1>
<p class="sub">Yours only. Do not put this page on the projector — <a href="/board" target="_blank">/board</a> is the one for the room.</p>
<div class="card" id="login">
  <label for="key"><b>Admin key</b></label>
  <p class="dim" style="margin:4px 0 10px;font-size:.88rem">Printed by <code>make hub-07</code>.</p>
  <input id="key" type="password" autocomplete="off">
  <p style="margin:12px 0 0"><button class="go" id="enter">Unlock</button></p>
</div>
<div id="panel" hidden>
  <div class="card"><b id="phase"></b> <span class="clock" id="clock"></span>
    <div class="dim" id="stats"></div></div>
  <p><button class="go" data-a="start_grafana">Start round 1 · Grafana</button></p>
  <p><button class="go" data-a="start_kagent">Start round 2 · unlock kagent</button></p>
  <p><button data-a="add_minute">+1 minute</button>
     <button data-a="finish">Finish</button></p>
  <details><summary>Reset</summary>
    <p><button data-a="lobby">Back to lobby (keep scores)</button>
       <button data-a="reset_scores" data-confirm="Wipe every solve and go back to the lobby?">Wipe scores</button></p>
    <p class="dim">Players stay joined either way.</p></details>
  <h2>Agents kagent is serving</h2><div id="agents" class="dim"></div>
  <h2>Players</h2>
  <p><button id="csv">Download emails (CSV)</button></p>
  <p id="msg" class="msg"></p>
</div>
<script>
const $=id=>document.getElementById(id);
let KEY="", A=null, skew=0;
try{KEY=sessionStorage.getItem("ctf-admin")||"";}catch(e){}
async function call(path,body){
  const r=await fetch(path,{method:"POST",headers:{"Content-Type":"application/json"},
    body:JSON.stringify(Object.assign({key:KEY},body||{}))});
  const d=await r.json().catch(()=>({})); if(!r.ok)throw new Error(d.error||("HTTP "+r.status)); return d;
}
function tick(){
  if(!A)return; const r=A.round;
  if(!r.round){$("clock").textContent="";return;}
  const left=Math.max(0,r.ends-(Date.now()+skew));
  $("clock").textContent=left>0?(Math.floor(left/60000)+":"+String(Math.floor(left%60000/1000)).padStart(2,"0")):"time is up";
}
async function refresh(){
  try{
    A=await call("/api/admin/state"); skew=(A.now||Date.now())-Date.now();
    $("login").hidden=true; $("panel").hidden=false;
    $("phase").textContent=A.round.phase;
    $("stats").textContent=A.players+" joined · round 1: "+A.rounds["1"].solves+" solves · round 2: "+A.rounds["2"].solves+" solves";
    $("agents").textContent=A.agents.length?A.agents.map(a=>a.name+(a.ready?"":" (starting)")).join(", "):"none yet";
    tick();
  }catch(e){ if($("panel").hidden&&KEY){$("key").value="";KEY="";alert(e.message);} }
}
$("enter").onclick=()=>{KEY=$("key").value.trim();try{sessionStorage.setItem("ctf-admin",KEY);}catch(e){} refresh();};
document.querySelectorAll("button[data-a]").forEach(b=>b.onclick=async()=>{
  if(b.dataset.confirm&&!confirm(b.dataset.confirm))return;
  try{await call("/api/admin/round",{action:b.dataset.a});$("msg").className="msg ok";$("msg").textContent="done";}
  catch(e){$("msg").className="msg bad";$("msg").textContent=e.message;}
  refresh();
});
$("csv").onclick=async()=>{
  try{const d=await call("/api/admin/players");
    const a=document.createElement("a");
    a.href=URL.createObjectURL(new Blob([d.csv],{type:"text/csv"}));a.download="ctf-players.csv";a.click();}
  catch(e){$("msg").className="msg bad";$("msg").textContent=e.message;}
};
if(KEY)refresh(); setInterval(()=>{if(KEY)refresh();},4000); setInterval(tick,500);
</script>""")


# -------------------------------------------------------------------- handler

class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "ctf"

    def log_message(self, *a):
        pass

    def _send(self, code, body=b"", ctype="text/html; charset=utf-8", headers=()):
        if isinstance(body, str):
            body = body.encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Referrer-Policy", "no-referrer")
        self.send_header("Cache-Control", "no-store")
        for k, v in headers:
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(body)

    def _json(self, code, obj, headers=()):
        self._send(code, json.dumps(obj), "application/json", headers)

    def _redirect(self, to, headers=()):
        self._send(302, b"", headers=(("Location", to),) + tuple(headers))

    def _client_ip(self):
        fwd = self.headers.get("X-Forwarded-For", "")
        return fwd.split(",")[0].strip() if fwd else self.client_address[0]

    def _cookie(self, name):
        for part in (self.headers.get("Cookie") or "").split(";"):
            k, _, v = part.strip().partition("=")
            if k == name:
                return v
        return ""

    def _player(self):
        return read_session(self._cookie(COOKIE))

    def _body(self, cap=8192):
        try:
            length = int(self.headers.get("Content-Length") or 0)
        except ValueError:
            return None
        if length > cap:
            self.close_connection = True
            return None
        try:
            obj = json.loads(self.rfile.read(length) or b"{}")
        except Exception:
            return None
        return obj if isinstance(obj, dict) else None

    def _set_cookie(self, name, value):
        secure = "; Secure" if PUBLIC_URL.startswith("https://") else ""
        return ("Set-Cookie", f"{name}={value}; Path=/; Max-Age=172800; "
                              f"HttpOnly; SameSite=Lax{secure}")

    # ---- the kagent gateway -------------------------------------------------
    #
    # The kagent ingress asks /gw/auth about every request. The answer is who
    # the player is (so kagent keeps their chats separate from everyone
    # else's) and whether kagent is unlocked yet. What a player may *change*
    # in kagent is not decided here -- that is the guard in front of the
    # controller (hub-08), which sees the real API call rather than a page URL.

    def _gw_auth(self):
        pid = read_session(self._cookie(GW_COOKIE))
        if not pid:
            return self._send(401, "join first\n", "text/plain")
        if not round_view()["kagent"]:
            return self._send(401, "kagent unlocks in round 2\n", "text/plain")
        # The dashboard is far more than a chat window: it has pages for
        # creating agents, models and tool servers. The guard refuses to save
        # any of them, but a player should not be looking at the forms at all.
        # Only the chat with an agent, and what that page loads, is let in;
        # anything else answers 401, which the ingress turns into a redirect
        # back to the CTF page.
        original = self.headers.get("X-Original-URL", "")
        if original and not GW_ALLOWED.match(urllib.parse.urlsplit(original).path):
            return self._send(401, "chat only\n", "text/plain")
        with LOCK:
            handle = STATE["players"][pid]["handle"]
        return self._send(200, "ok\n", "text/plain", (("X-User-Id", handle + "@ctf"),))

    def _gw_enter(self, query):
        pid = read_entry((query.get("t") or [""])[0])
        to = (query.get("to") or ["/"])[0]
        if not to.startswith("/") or to.startswith("//"):
            to = "/"
        if not pid:
            return self._redirect(PUBLIC_URL or "/")
        # A page rather than a redirect, because it runs on the kagent host
        # and so can tell the dashboard its first-run wizard has been seen.
        # The wizard walks through creating a model and an agent, none of
        # which a player can do.
        dest = json.dumps(to).replace("<", "\\u003c")
        body = ("<!doctype html><meta charset=utf-8><title>kagent</title>"
                "<script>try{localStorage.setItem('kagent-onboarding','true')}catch(e){}"
                f"location.replace({dest})</script>")
        return self._send(200, body, headers=(self._set_cookie(GW_COOKIE, session_token(pid)),))

    # ---- routes -------------------------------------------------------------

    def do_GET(self):
        url = urllib.parse.urlsplit(self.path)
        p = url.path.rstrip("/") or "/"
        query = urllib.parse.parse_qs(url.query)

        if p == "/healthz":
            return self._send(200, "ok\n", "text/plain")
        if p == "/gw/auth":
            return self._gw_auth()
        if p == "/gw/enter":
            return self._gw_enter(query)
        if p == "/":
            return self._send(200, PLAY if self._player() else join_page())
        if p == "/board":
            return self._send(200, BOARD)
        if p == "/admin":
            return self._send(200, ADMIN)
        if p == "/api/board":
            return self._json(200, {**board(), "now": now_ms()})
        if p == "/api/me":
            pid = self._player()
            if not pid:
                return self._json(401, {"error": "join first"})
            return self._json(200, {**me(pid), "now": now_ms()})
        if p == "/go/kagent":
            pid = self._player()
            if not pid or not KAGENT_URL:
                return self._redirect("/")
            if not round_view()["kagent"]:
                return self._redirect("/")
            to = (query.get("to") or ["/"])[0]
            return self._redirect(f"{KAGENT_URL}/gw/enter?" + urllib.parse.urlencode(
                {"t": entry_token(pid), "to": to}))
        return self._send(404, page("Not found", "<h1>Not found</h1>"))

    def do_POST(self):
        p = urllib.parse.urlsplit(self.path).path.rstrip("/")
        body = self._body()
        if body is None:
            return self._json(400, {"error": "bad request"})

        if p == "/api/join":
            if not rate_ok("join|" + self._client_ip(), JOIN_PER_MIN):
                return self._json(429, {"error": "too many attempts — wait a minute"})
            pid, err = join(body.get("email", ""))
            if err:
                return self._json(400, {"error": err})
            return self._json(200, {"ok": True},
                              (self._set_cookie(COOKIE, session_token(pid)),))

        if p == "/api/submit":
            pid = self._player()
            if not pid:
                return self._json(401, {"error": "join first"})
            code, out = submit(pid, str(body.get("flag", "")), str(body.get("answer", ""))[:200])
            return self._json(code, out)

        if p.startswith("/api/admin/"):
            if not ADMIN_KEY:
                return self._json(503, {"error": "no admin key configured"})
            if not rate_ok("admin|" + self._client_ip(), 120):
                return self._json(429, {"error": "too many attempts"})
            if not hmac.compare_digest(str(body.get("key", "")), ADMIN_KEY):
                return self._json(403, {"error": "wrong admin key"})
            if p == "/api/admin/state":
                b = board()
                return self._json(200, {"round": b["round"], "players": b["players"],
                                        "rounds": b["rounds"], "agents": agents(),
                                        "now": now_ms()})
            if p == "/api/admin/round":
                err = admin_action(str(body.get("action", "")))
                return self._json(400, {"error": err}) if err else self._json(200, {"ok": True})
            if p == "/api/admin/players":
                with LOCK:
                    rows = sorted(STATE["players"].items(), key=lambda kv: kv[1]["joined"])
                lines = ["email,handle,score,joined_utc"]
                for pid, pl in rows:
                    ts = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(pl["joined"] / 1000))
                    em = '"' + pl["email"].replace('"', '""') + '"'
                    lines.append(f'{em},{pl["handle"]},{score(pid)},{ts}')
                return self._json(200, {"csv": "\n".join(lines) + "\n"})

        return self._json(404, {"error": "not found"})


def main():
    if not SECRET:
        raise SystemExit("CTF_SECRET is not set — refusing to sign sessions with an empty key")
    load_state()
    port = int(os.environ.get("PORT", "8080"))
    print(f"ctf on :{port} — {len(STATE['players'])} player(s), phase {STATE['phase']}, "
          f"{len(FLAGS)} flags / {MAX_POINTS} pts, "
          f"admin {'enabled' if ADMIN_KEY else 'DISABLED (no ADMIN_KEY)'}", flush=True)
    ThreadingHTTPServer(("0.0.0.0", port), Handler).serve_forever()


if __name__ == "__main__":
    main()
