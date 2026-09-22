#!/usr/bin/env python3
"""Webhook sink and wall for the workshop.

Attendees' daily-report CronJobs POST here; each attendee watches their own
page; the instructor puts /wall on the projector.

No database, no volume, no code registry. A code is an opaque routing key the
server never registers -- POST /hook/<anything> is accepted and buffered under
that key. So there is nothing a restart can invalidate: an attendee's .env keeps
working, their CronJob keeps posting, and the page repopulates. History that
matters lives in the browser's localStorage, not here.

Everything rendered is escaped. The body is attacker-controlled text written by
people who have just been taught to automate things, and /wall goes on a
projector.
"""
import hmac, html, json, os, re, secrets, threading, time
from collections import defaultdict, deque
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

MAX_BODY = 256 * 1024          # per delivery
KEEP_PER_CODE = 30             # a month of dailies
MAX_CODES = 500                # so a loop cannot exhaust memory
RATE_PER_MIN = 10              # per code
CODE_RE = re.compile(r"^[a-z0-9-]{3,40}$")

# ---------------------------------------------------------------- credentials
#
# Attendees claim a slot with the passphrase from the slides and get a complete
# .env back. One download beats four copy-pastes off a projector.
#
# The claim ledger is the one piece of genuinely durable state here. Report
# history can live in a browser because losing it is harmless; a lost ledger
# means the server starts re-issuing credentials that people already hold.
JOIN_PASSPHRASE = os.environ.get("JOIN_PASSPHRASE", "").strip()
SECRETS_DIR = os.environ.get("SECRETS_DIR", "/secrets")
LEDGER_PATH = os.environ.get("LEDGER_PATH", "/data/ledger.json")
MCP_ENDPOINT = os.environ.get("MCP_ENDPOINT", "").strip()
PUBLIC_URL = os.environ.get("PUBLIC_URL", "").strip()
GRAFANA_URL = os.environ.get("GRAFANA_URL", "").strip()
REPO_URL = os.environ.get("REPO_URL", "https://github.com/DMajrekar/kagent-civo-workshop").strip()
SIGNUP_URL = os.environ.get("SIGNUP_URL", "https://www.civo.com/seminar-signup").strip()
JOIN_ATTEMPTS_PER_MIN = 12

LOCK = threading.Lock()
LEDGER_LOCK = threading.Lock()
JOIN_HITS = defaultdict(lambda: deque())   # client ip -> recent attempt times
BOX = {}                                  # code -> deque of deliveries
HITS = defaultdict(lambda: deque())       # code -> recent post times
SEQ = [0]

ADJECTIVES = ["amber","brisk","calm","coral","dusky","eager","fleet","golden",
              "hazel","ivory","jade","keen","lunar","misty","noble","olive",
              "prism","quiet","rapid","sable","tidal","umber","vivid","warm"]
NOUNS = ["otter","falcon","cedar","harbor","lantern","meadow","nimbus","onyx",
         "pebble","quarry","ridge","summit","thicket","vessel","willow","yarrow",
         "anvil","beacon","cobalt","delta","ember","fjord","grove","hollow"]


def now_ms():
    return int(time.time() * 1000)


def _read_pool(name):
    """One credential per line, blanks and #comments ignored."""
    path = os.path.join(SECRETS_DIR, name)
    try:
        with open(path) as fh:
            return [ln.strip() for ln in fh
                    if ln.strip() and not ln.strip().startswith("#")]
    except OSError:
        return []


def _mcp_tokens():
    # hub-06 writes "attendee-01 <token>" per line; accept either shape.
    out = []
    for ln in _read_pool("mcp-tokens.txt"):
        parts = ln.split()
        out.append(parts[-1] if parts else ln)
    return out


def _load_ledger():
    try:
        with open(LEDGER_PATH) as fh:
            return json.load(fh)
    except Exception:
        return {"claims": {}, "next": 0}


def _save_ledger(led):
    tmp = LEDGER_PATH + ".tmp"
    os.makedirs(os.path.dirname(LEDGER_PATH), exist_ok=True)
    with open(tmp, "w") as fh:
        json.dump(led, fh)
        fh.flush()
        os.fsync(fh.fileno())
    os.replace(tmp, LEDGER_PATH)      # atomic: never a half-written ledger


def normalise(name):
    return re.sub(r"[^a-z0-9]+", "-", name.strip().lower()).strip("-")[:40]


def claim_slot(name):
    """Assign (or return) this person's slot. Same name always gets the same one."""
    key = normalise(name)
    if not key:
        return None, "give us a name or handle so you can get this back later"

    relax = _read_pool("relax-keys.txt")
    if not relax:
        return None, "no model keys are loaded on the server — tell the instructor"
    tokens = _mcp_tokens()

    with LEDGER_LOCK:
        led = _load_ledger()
        if key in led["claims"]:
            slot = led["claims"][key]          # returning attendee
        else:
            idx = led["next"]
            slot = {"i": idx, "code": f"{ADJECTIVES[idx % len(ADJECTIVES)]}-"
                                      f"{NOUNS[(idx * 7 + 3) % len(NOUNS)]}-{idx:02d}"}
            led["claims"][key] = slot
            led["next"] = idx + 1
            _save_ledger(led)

    idx = slot["i"]
    # Never block an attendee two minutes into the session. If there are more
    # people than keys, wrap round and share -- degraded, but working. The
    # instructor is told loudly; the attendee is told quietly.
    i = idx % len(relax)
    # One key in the pool means it is meant to be shared by everyone; that is a
    # setup choice, not a shortfall, so attendees are not told anything is
    # wrong. More than one and running out IS an accident -- flag that.
    single_shared_key = len(relax) == 1
    shared = idx >= len(relax) and not single_shared_key
    if shared:
        print(f"WARNING: credential pool oversubscribed — claim #{idx + 1} is "
              f"sharing key #{i + 1} of {len(relax)}. Add more keys to "
              f"relax-keys.txt and re-run hub-07.", flush=True)

    return {
        "name": key,
        "slot": idx + 1,
        "code": slot["code"],
        "shared": shared,
        "pool": len(relax),
        "relax_key": relax[i],
        "mcp_token": (tokens[idx % len(tokens)] if tokens else ""),
    }, None


def env_file(slot):
    base = PUBLIC_URL or ""
    note = ""
    if slot.get("shared"):
        note = ("# NOTE: there were more attendees than model keys, so this key is\n"
                "# shared with someone else. It works; if the agent starts reporting\n"
                "# quota errors, mention it to the instructor.\n")
    elif slot.get("pool") == 1:
        note = "# The model key below is the workshop's shared key.\n"
    return f"""# Workshop credentials for {slot['name']} (slot {slot['slot']}).
{note}
# Generated by the workshop hub. Keep this file out of version control.

# ---- your own Civo account -------------------------------------------------
# Get a key at https://dashboard.civo.com/security
CIVO_API_KEY=
CIVO_REGION=lon1

# Your cluster. Change it if you like; it only has to be unique within your
# own Civo account.
CLUSTER_NAME=kagent-workshop
CIVO_NODE_SIZE=g4s.kube.medium
CIVO_NODE_COUNT=2

# ---- provided for you ------------------------------------------------------
RELAX_API_KEY={slot['relax_key']}
RELAX_BASE_URL=https://api.relax.ai/v1
RELAX_MODEL=DeepSeek-V4-Pro

MCP_ENDPOINT={MCP_ENDPOINT}
MCP_TOKEN={slot['mcp_token']}

REPORT_WEBHOOK_URL={base}/hook/{slot['code']}
"""


def add(code, body, ctype):
    with LOCK:
        if code not in BOX and len(BOX) >= MAX_CODES:
            return None, "too many codes on this server"
        hits = HITS[code]
        cutoff = time.time() - 60
        while hits and hits[0] < cutoff:
            hits.popleft()
        if len(hits) >= RATE_PER_MIN:
            return None, "rate limit: max %d posts per minute per code" % RATE_PER_MIN
        hits.append(time.time())
        SEQ[0] += 1
        item = {"id": SEQ[0], "at": now_ms(), "type": ctype, "body": body}
        BOX.setdefault(code, deque(maxlen=KEEP_PER_CODE)).append(item)
        return item, None


def items(code):
    with LOCK:
        return list(BOX.get(code, []))


def all_items():
    """Everything for the wall, minus the step's own verification traffic.

    hub-07 posts a smoke delivery (and a hostile payload) on every run to prove
    the path works. Those are not reports and must never reach the projector.
    """
    with LOCK:
        out = []
        for code, dq in BOX.items():
            if code.startswith(("smoke-", "smoke_")):
                continue
            for it in dq:
                out.append({**it, "code": code})
        return sorted(out, key=lambda i: -i["at"])[:200]


# --------------------------------------------------------------------- pages

STYLE = """
:root{--bg:#fbfaf8;--fg:#1a1a19;--dim:#6b6a67;--line:#e2e0dc;--card:#fff;--accent:#b4530a}
@media(prefers-color-scheme:dark){:root{--bg:#171715;--fg:#ece9e4;--dim:#9a9791;--line:#2f2e2b;--card:#1f1f1d;--accent:#e08b4c}}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--fg);font:15px/1.55 ui-sans-serif,system-ui,-apple-system,"Segoe UI",sans-serif}
.wrap{max-width:820px;margin:0 auto;padding:32px 20px 64px}
h1{font-size:1.5rem;margin:0 0 4px;letter-spacing:-.02em}
.sub{color:var(--dim);margin:0 0 28px}
code,pre{font-family:ui-monospace,SFMono-Regular,Menlo,monospace}
.code{font-size:2rem;font-weight:600;letter-spacing:-.01em;color:var(--accent)}
.url{background:var(--card);border:1px solid var(--line);border-radius:8px;padding:12px 14px;
     word-break:break-all;font-size:.9rem;margin:12px 0 4px}
button{font:inherit;padding:9px 16px;border-radius:8px;border:1px solid var(--line);
       background:var(--card);color:var(--fg);cursor:pointer}
button:hover{border-color:var(--accent)}
.item{background:var(--card);border:1px solid var(--line);border-radius:10px;margin:14px 0;overflow:hidden}
.meta{display:flex;gap:12px;align-items:baseline;padding:9px 14px;border-bottom:1px solid var(--line);
      color:var(--dim);font-size:.82rem}
.meta .who{color:var(--accent);font-weight:600}
pre.body{margin:0;padding:14px;white-space:pre-wrap;word-break:break-word;font-size:.86rem;max-height:340px;overflow:auto}
.empty{color:var(--dim);border:1px dashed var(--line);border-radius:10px;padding:28px;text-align:center}
.tag{margin-left:auto;font-size:.75rem}
"""

def page(title, body):
    return f"""<!doctype html><html><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>{html.escape(title)}</title><style>{STYLE}</style></head>
<body><div class="wrap">{body}</div></body></html>"""


def landing_page():
    """The QR code target: everything anyone needs, on one screen."""
    graf = (f'<a class="card" href="{html.escape(GRAFANA_URL)}" target="_blank" rel="noopener">'
            f'<span class="k">2 &middot; The logs</span>'
            f'<span class="d">Grafana and Loki, read-only. The same seven days your '
            f'agent can see — go and find something in it yourself.</span></a>'
            if GRAFANA_URL else "")
    return page("Workshop links", f"""
<h1>kagent on Civo</h1>
<p class="sub">Everything you need, in the order you need it.</p>

<div class="cards">
  <a class="card go" href="{html.escape(SIGNUP_URL)}" target="_blank" rel="noopener">
    <span class="k">1 &middot; Sign up with Civo</span>
    <span class="d">You need a Civo account to build your cluster. Start here if
    you have not already.</span>
  </a>

  {graf}

  <a class="card" href="{html.escape(REPO_URL)}" target="_blank" rel="noopener">
    <span class="k">3 &middot; Clone the repo</span>
    <span class="d">Every step of the workshop is a <code>make</code> target in
    here. Clone it somewhere you can find again.</span>
  </a>

  <a class="card" href="/join">
    <span class="k">4 &middot; Get your .env</span>
    <span class="d">Passphrase from the slides, then download a ready-made
    <code>.env</code> and save it inside the repo you just cloned. Then
    <code>make doctor</code>.</span>
  </a>

  <a class="card" id="inbox" href="/" hidden>
    <span class="k">5 &middot; Your report inbox</span>
    <span class="d">Your progress through the workshop, and the reports your
    agent posts. Code: <code class="mycode"></code></span>
  </a>

</div>

<style>
.cards{{display:flex;flex-direction:column;gap:10px;margin-top:22px}}
.card{{display:block;background:var(--card);border:1px solid var(--line);border-radius:12px;
      padding:15px 17px;text-decoration:none;color:inherit;transition:border-color .15s}}
.card:hover{{border-color:var(--accent)}}
.card .k{{display:block;font-weight:600;font-size:.98rem;margin-bottom:3px}}
.card .d{{display:block;color:var(--dim);font-size:.86rem;line-height:1.45}}
.card.go{{border-color:var(--accent);border-width:1.5px}}
.card.go .k{{color:var(--accent)}}
</style>

<script>
// Only show the inbox card once they have actually claimed a code.
try{{
  const c=localStorage.getItem("workshop-code");
  if(c){{
    const a=document.getElementById("inbox");
    a.href="/c/"+c;
    a.querySelector(".mycode").textContent=c;
    a.hidden=false;
  }}
}}catch(e){{}}
</script>""")


def inbox_page(code):
    return page(f"Inbox — {code}", """
<h1>{{CODE}}</h1>
<p class="sub">Reports from your agent appear here. They are kept in this
browser — nothing on this page is sent anywhere.</p>

<div id="list"><div class="empty">Nothing yet. Trigger your report job and it will show up.</div></div>

<style>
</style>

<script>
const CODE={{CODE_JSON}}, KEY="workshop-archive-"+CODE, PKEY="workshop-progress-"+CODE;
// ---- reports --------------------------------------------------------------
function load(){try{return JSON.parse(localStorage.getItem(KEY)||"[]");}catch(e){return [];}}
function save(a){try{localStorage.setItem(KEY,JSON.stringify(a.slice(-60)));}catch(e){}}
function fmt(ms){const d=new Date(ms);return d.toLocaleString();}
function render(items){
  const el=document.getElementById("list");
  el.textContent="";
  if(!items.length){const e=document.createElement("div");e.className="empty";
    e.textContent="Nothing yet. Trigger your report job and it will show up.";el.append(e);return;}
  for(const it of items){
    const d=document.createElement("div");d.className="item";
    const m=document.createElement("div");m.className="meta";
    const t=document.createElement("span");t.textContent=fmt(it.at);
    const ty=document.createElement("span");ty.className="tag";ty.textContent=it.type||"";
    m.append(t,ty);
    const p=document.createElement("pre");p.className="body";
    p.textContent=it.body;           // textContent, never innerHTML
    d.append(m,p);el.append(d);
  }
}
function merge(a,b){const seen=new Set(),out=[];
  for(const it of [...b,...a]){const k=it.id+"|"+it.at;if(!seen.has(k)){seen.add(k);out.push(it);}}
  return out.sort((x,y)=>y.at-x.at);}
let archive=load();
render(archive);
async function poll(){
  try{const r=await fetch("/api/c/"+CODE);const live=(await r.json()).items||[];
    archive=merge(archive,live);save(archive);render(archive);
  }catch(e){}
}
poll();setInterval(poll,5000);
</script>"""
            .replace("{{CODE}}", html.escape(code))

            .replace("{{CODE_JSON}}", json.dumps(code)))


WALL = page("The wall", """
<h1>The wall</h1>
<p class="sub">Every report, as it lands.</p>
<div id="list"><div class="empty">Waiting for the first report…</div></div>
<script>
function fmt(ms){return new Date(ms).toLocaleTimeString();}
async function poll(){
  let items=[];
  try{items=(await (await fetch("/api/wall")).json()).items||[];}catch(e){return;}
  const el=document.getElementById("list");el.textContent="";
  if(!items.length){const e=document.createElement("div");e.className="empty";
    e.textContent="Waiting for the first report…";el.append(e);return;}
  for(const it of items){
    const d=document.createElement("div");d.className="item";
    const m=document.createElement("div");m.className="meta";
    const w=document.createElement("span");w.className="who";w.textContent=it.code;
    const t=document.createElement("span");t.textContent=fmt(it.at);
    m.append(w,t);
    const p=document.createElement("pre");p.className="body";
    p.textContent=it.body;           // textContent, never innerHTML
    d.append(m,p);el.append(d);
  }
}
poll();setInterval(poll,4000);
</script>""")


JOIN = page("Join the workshop", """
<h1>Get your workshop credentials</h1>
<p class="sub">Enter the passphrase from the slides and you'll get a ready-made
<code>.env</code> file. Add your Civo key below and it is complete — save it
next to the README and run <code>make doctor</code>.</p>

<form id="f" autocomplete="off">
  <p><label>Passphrase from the slides<br>
    <input id="pass" type="text" spellcheck="false" autocapitalize="none"></label></p>
  <p><label>Your name or handle<br>
    <input id="name" type="text" spellcheck="false" autocapitalize="none"></label>
    <br><span class="sub" style="font-size:.82rem">Used to give you the same
    credentials back if you reload or switch device.</span></p>
  <p><label>Your Civo API key <span style="font-weight:400">(optional)</span><br>
    <input id="civo" type="password" spellcheck="false" autocapitalize="none"
           autocomplete="off" placeholder="paste it here and the .env is complete"></label>
    <br><span class="sub" style="font-size:.82rem">From
    <a href="https://dashboard.civo.com/security" target="_blank" rel="noopener">dashboard.civo.com/security</a>.
    This never leaves your browser — it is pasted into the file on this page, not
    sent to us. Leave it blank and add it to the file yourself.</span></p>
  <p><button type="submit">Get my credentials</button></p>
</form>
<div id="out"></div>

<style>
input{font:inherit;padding:9px 12px;border-radius:8px;border:1px solid var(--line);
      background:var(--card);color:var(--fg);width:100%;max-width:360px;margin-top:5px}
label{color:var(--dim);font-size:.88rem}
.err{color:#c0392b;margin-top:12px}
@media(prefers-color-scheme:dark){.err{color:#ff8b7a}}
</style>

<script>
const f=document.getElementById("f"), out=document.getElementById("out");
// A remembered name is what gives someone their credentials back on a reload
// or a second device. Show that it is remembered rather than just pre-filling
// the box, so a throwaway name does not get reused without anyone noticing.
try{
  const n=localStorage.getItem("workshop-name");
  if(n){
    const box=document.getElementById("name");
    box.value=n;
    const hint=document.createElement("span");
    hint.className="sub";
    hint.style.cssText="display:block;font-size:.82rem;margin-top:4px";
    hint.textContent="Remembered from last time. ";
    const clear=document.createElement("a");
    clear.href="#"; clear.textContent="Not you? Start fresh.";
    clear.onclick=ev=>{
      ev.preventDefault();
      try{localStorage.removeItem("workshop-name");localStorage.removeItem("workshop-code");}catch(e){}
      box.value=""; hint.remove(); box.focus();
    };
    hint.append(clear);
    box.parentNode.parentNode.appendChild(hint);
  }
}catch(e){}
f.onsubmit=async ev=>{
  ev.preventDefault();
  out.textContent="";
  const passphrase=document.getElementById("pass").value;
  const name=document.getElementById("name").value;
  let r, d;
  try{
    r=await fetch("/api/join",{method:"POST",headers:{"Content-Type":"application/json"},
        body:JSON.stringify({passphrase,name})});
    d=await r.json();
  }catch(e){ out.innerHTML='<p class="err">Could not reach the server.</p>'; return; }
  if(!r.ok){
    const p=document.createElement("p"); p.className="err";
    p.textContent=d.error||"Something went wrong.";   // textContent, never innerHTML
    out.append(p); return;
  }
  try{localStorage.setItem("workshop-name",name);localStorage.setItem("workshop-code",d.code);}catch(e){}

  // Splice the Civo key in here, in the browser. It is the attendee's own
  // credential for their own account and the server has no use for it, so it
  // is never sent -- the field above is not part of the request.
  const civo=document.getElementById("civo").value.trim();
  let envText=d.env;
  if(civo) envText=envText.replace(/^CIVO_API_KEY=.*$/m,"CIVO_API_KEY="+civo);

  out.textContent="";
  const h=document.createElement("div");
  h.innerHTML='<p class="sub">You are attendee <strong class="n"></strong>. '+
              'Your report inbox is <code class="c"></code>.</p>'+
              '<p class="shared err" hidden>Heads up: there were more people than '+
              'model keys, so yours is shared with someone else. It works — just '+
              'mention it to the instructor if you hit a quota error.</p>';
  h.querySelector(".n").textContent=d.slot;
  h.querySelector(".c").textContent=d.code;
  if(d.shared) h.querySelector(".shared").hidden=false;
  const pre=document.createElement("pre"); pre.className="body";
  pre.style.cssText="background:var(--card);border:1px solid var(--line);border-radius:10px;padding:14px;overflow:auto";
  // Redact the Civo key in the on-screen preview: people do this on a shared
  // screen, and the download still carries the real value.
  pre.textContent=civo ? envText.replace(/^(CIVO_API_KEY=).*$/m,"$1"+"*".repeat(12)) : envText;
  const dl=document.createElement("button");
  dl.textContent="Download .env";
  dl.onclick=()=>{
    const b=new Blob([envText],{type:"text/plain"});
    const a=document.createElement("a");
    a.href=URL.createObjectURL(b); a.download=".env"; a.click();
    URL.revokeObjectURL(a.href);
  };
  const cp=document.createElement("button");
  cp.textContent="Copy"; cp.style.marginLeft="8px";
  cp.onclick=()=>{navigator.clipboard.writeText(envText).then(()=>{
    cp.textContent="Copied"; setTimeout(()=>cp.textContent="Copy",1500);});};
  const inbox=document.createElement("button");
  inbox.textContent="Open my inbox"; inbox.style.marginLeft="8px";
  inbox.onclick=()=>{location.href="/c/"+d.code;};
  out.append(h,dl,cp,inbox,pre);
  f.style.display="none";
};
</script>""")


def join_rate_ok(ip):
    """Throttle passphrase attempts per client: this endpoint hands out keys."""
    with LOCK:
        hits = JOIN_HITS[ip]
        cutoff = time.time() - 60
        while hits and hits[0] < cutoff:
            hits.popleft()
        if len(hits) >= JOIN_ATTEMPTS_PER_MIN:
            return False
        hits.append(time.time())
        return True


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "workshop-sink"

    def log_message(self, *a):
        pass

    def _send(self, code, body, ctype="text/html; charset=utf-8"):
        if isinstance(body, str):
            body = body.encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("X-Content-Type-Options", "nosniff")
        # The pages build their own DOM with textContent; no inline eval needed
        # beyond our own script blocks.
        self.send_header("Referrer-Policy", "no-referrer")
        self.end_headers()
        self.wfile.write(body)

    def _json(self, code, obj):
        self._send(code, json.dumps(obj), "application/json")

    def _client_ip(self):
        fwd = self.headers.get("X-Forwarded-For", "")
        return (fwd.split(",")[0].strip() if fwd else self.client_address[0])

    def _join(self):
        if not JOIN_PASSPHRASE:
            return self._json(503, {"error": "credential handout is not configured "
                                             "on this server"})
        if not join_rate_ok(self._client_ip()):
            return self._json(429, {"error": "too many attempts — wait a minute "
                                             "and try again"})
        try:
            length = int(self.headers.get("Content-Length") or 0)
        except ValueError:
            return self._json(400, {"error": "bad request"})
        if length > 8192:
            self._drain(length)
            return self._json(413, {"error": "request too large"})
        try:
            body = json.loads(self.rfile.read(length) or b"{}")
        except Exception:
            return self._json(400, {"error": "bad request"})

        # compare_digest so a wrong passphrase cannot be narrowed down by timing
        if not hmac.compare_digest(str(body.get("passphrase", "")).strip(),
                                   JOIN_PASSPHRASE):
            return self._json(403, {"error": "that passphrase is not right — "
                                             "check the slides"})

        slot, err = claim_slot(str(body.get("name", "")))
        if err:
            return self._json(409, {"error": err})
        # Deliberately not logged: this response carries live credentials.
        return self._json(200, {"slot": slot["slot"], "code": slot["code"],
                                "shared": slot.get("shared", False),
                                "env": env_file(slot)})

    def _claims(self):
        """Instructor view: how many have claimed. Never returns a credential."""
        if not JOIN_PASSPHRASE:
            return self._json(503, {"error": "handout not configured"})
        if not join_rate_ok(self._client_ip()):
            return self._json(429, {"error": "too many attempts"})
        try:
            length = int(self.headers.get("Content-Length") or 0)
            body = json.loads(self.rfile.read(min(length, 8192)) or b"{}")
        except Exception:
            return self._json(400, {"error": "bad request"})
        if not hmac.compare_digest(str(body.get("passphrase", "")).strip(),
                                   JOIN_PASSPHRASE):
            return self._json(403, {"error": "wrong passphrase"})
        with LEDGER_LOCK:
            led = _load_ledger()
        pool = len(_read_pool("relax-keys.txt"))
        claimed = len(led["claims"])
        shared_by_design = pool == 1
        return self._json(200, {
            "pool": pool,
            "claimed": claimed,
            # With a single key everyone is meant to share it, so neither
            # "remaining" nor "oversubscribed" means anything.
            "mode": "one shared key" if shared_by_design else "one key each",
            "remaining": None if shared_by_design else max(0, pool - claimed),
            "oversubscribed": 0 if shared_by_design else max(0, claimed - pool),
            "names": sorted(led["claims"].keys()),
        })

    def _drain(self, length, cap=16 * 1024 * 1024):
        """Read and discard a request body we are going to reject."""
        left = min(length, cap)
        while left > 0:
            chunk = self.rfile.read(min(65536, left))
            if not chunk:
                break
            left -= len(chunk)
        if length > cap:
            # Too big to politely swallow; hang up instead of reading forever.
            self.close_connection = True

    def do_GET(self):
        p = self.path.split("?")[0].rstrip("/") or "/"
        if p == "/healthz":
            return self._send(200, "ok\n", "text/plain")
        if p == "/":
            return self._send(200, landing_page())
        if p == "/wall":
            return self._send(200, WALL)
        if p == "/join":
            return self._send(200, JOIN)
        if p == "/api/wall":
            return self._json(200, {"items": all_items()})
        if p.startswith("/c/"):
            code = p[3:]
            if not CODE_RE.match(code):
                return self._send(404, page("Not found", "<h1>Not found</h1>"))
            return self._send(200, inbox_page(code))
        if p.startswith("/api/c/"):
            code = p[7:]
            if not CODE_RE.match(code):
                return self._json(404, {"error": "bad code"})
            return self._json(200, {"code": code, "items": items(code)})
        return self._send(404, page("Not found", "<h1>Not found</h1>"))

    def do_POST(self):
        p = self.path.split("?")[0].rstrip("/")

        if p == "/api/join":
            return self._join()

        if p == "/api/claims":
            return self._claims()

        if not p.startswith("/hook/"):
            return self._json(404, {"error": "post to /hook/<your-code>"})
        code = p[6:]
        if not CODE_RE.match(code):
            return self._json(400, {"error": "code must be 3-40 chars of a-z 0-9 -"})
        try:
            length = int(self.headers.get("Content-Length") or 0)
        except ValueError:
            return self._json(400, {"error": "bad Content-Length"})
        if length > MAX_BODY:
            # Drain before replying. Answering 413 while the client is still
            # sending leaves it with a broken pipe rather than our error, so
            # the caller sees a transport failure and cannot tell why.
            self._drain(length)
            return self._json(413, {"error": f"body too large (max {MAX_BODY} bytes)"})
        raw = self.rfile.read(length) if length else b""
        body = raw.decode("utf-8", "replace")
        # Slack-style {"text": "..."} is the common shape; unwrap it so the
        # page shows the message rather than the envelope.
        ctype = (self.headers.get("Content-Type") or "").split(";")[0]
        if ctype == "application/json":
            try:
                obj = json.loads(body)
                if isinstance(obj, dict) and isinstance(obj.get("text"), str):
                    body = obj["text"]
                else:
                    body = json.dumps(obj, indent=2)
            except Exception:
                pass
        item, err = add(code, body, ctype or "text/plain")
        if err:
            return self._json(429, {"error": err})
        return self._json(202, {"ok": True, "id": item["id"]})


def main():
    port = int(os.environ.get("PORT", "8080"))
    n_keys = len(_read_pool("relax-keys.txt"))
    led = _load_ledger()
    print(f"webhook sink on :{port}", flush=True)
    print(f"  credential handout: "
          f"{'enabled' if JOIN_PASSPHRASE else 'DISABLED (no JOIN_PASSPHRASE)'}, "
          f"{n_keys} key(s) in the pool, {len(led['claims'])} already claimed",
          flush=True)
    ThreadingHTTPServer(("0.0.0.0", port), Handler).serve_forever()


main()
