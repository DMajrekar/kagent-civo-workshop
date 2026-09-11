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
import html, json, os, re, threading, time
from collections import defaultdict, deque
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

MAX_BODY = 256 * 1024          # per delivery
KEEP_PER_CODE = 30             # a month of dailies
MAX_CODES = 500                # so a loop cannot exhaust memory
RATE_PER_MIN = 10              # per code
CODE_RE = re.compile(r"^[a-z0-9-]{3,40}$")

LOCK = threading.Lock()
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
    with LOCK:
        out = []
        for code, dq in BOX.items():
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


LANDING = page("Workshop report wall", """
<h1>Your report inbox</h1>
<p class="sub">Your agent's daily report lands here. Keep this page — it is yours.</p>
<div id="out"></div>
<script>
const ADJ=%s, NOUN=%s;
function mint(){return ADJ[Math.floor(Math.random()*ADJ.length)]+"-"+NOUN[Math.floor(Math.random()*NOUN.length)];}
let code=null;
try{code=localStorage.getItem("workshop-code");}catch(e){}
if(!code){code=mint();try{localStorage.setItem("workshop-code",code);}catch(e){}}
const url=location.origin+"/hook/"+code;
const out=document.getElementById("out");
const h=document.createElement("div");
h.innerHTML='<div class="code"></div>'+
 '<p class="sub" style="margin:6px 0 14px">Put this in your <code>.env</code> as <code>REPORT_WEBHOOK_URL</code>:</p>'+
 '<div class="url"></div>';
h.querySelector(".code").textContent=code;
h.querySelector(".url").textContent=url;
const b=document.createElement("button");
b.textContent="Copy URL";
b.onclick=()=>{navigator.clipboard.writeText(url).then(()=>{b.textContent="Copied";setTimeout(()=>b.textContent="Copy URL",1500);});};
const v=document.createElement("button");
v.textContent="Open my inbox";v.style.marginLeft="8px";
v.onclick=()=>{location.href="/c/"+code;};
out.append(h,b,v);
</script>""" % (json.dumps(ADJECTIVES), json.dumps(NOUNS)))


def inbox_page(code):
    return page(f"Inbox — {code}", """
<h1>%s</h1>
<p class="sub">Reports appear here as your CronJob posts them.
Older ones are kept in <em>this browser</em>.</p>
<div id="list"><div class="empty">Nothing yet. Trigger your report job and it will show up.</div></div>
<script>
const CODE=%s, KEY="workshop-archive-"+CODE;
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
    archive=merge(archive,live);save(archive);render(archive);}catch(e){}
}
poll();setInterval(poll,5000);
</script>""" % (html.escape(code), json.dumps(code)))


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
            return self._send(200, LANDING)
        if p == "/wall":
            return self._send(200, WALL)
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
    print(f"webhook sink on :{port}", flush=True)
    ThreadingHTTPServer(("0.0.0.0", port), Handler).serve_forever()


main()
