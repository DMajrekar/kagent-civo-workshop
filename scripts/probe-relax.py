#!/usr/bin/env python3
"""Probe relax.ai models for the tool-calling behaviour kagent depends on.

kagent agents are a tool-call loop: the model must emit well-formed tool_calls,
accept the results back, and produce a coherent answer. A model that chats
beautifully but calls tools unreliably is useless here. This checks four things
that actually break in practice.

  ./scripts/probe-relax.py              # probe every chat model
  ./scripts/probe-relax.py MODEL [...]  # probe specific models
"""
import json, os, sys, time, urllib.request, urllib.error

BASE = os.environ.get("RELAX_BASE_URL", "https://api.relax.ai/v1").rstrip("/")
KEY  = os.environ.get("RELAX_API_KEY")
if not KEY:
    sys.exit("RELAX_API_KEY not set (source scripts/lib.sh or export it)")

G, R, Y, D, B, X = "\033[32m", "\033[31m", "\033[33m", "\033[2m", "\033[1m", "\033[0m"

TOOLS = [
    {"type": "function", "function": {
        "name": "query_logs",
        "description": "Query application logs from Loki using a LogQL selector.",
        "parameters": {"type": "object", "properties": {
            "query": {"type": "string", "description": "LogQL query, e.g. {service=\"checkout\"} |= \"error\""},
            "hours": {"type": "integer", "description": "How many hours back to search"},
        }, "required": ["query", "hours"]}}},
    {"type": "function", "function": {
        "name": "list_services",
        "description": "List all services currently emitting logs.",
        "parameters": {"type": "object", "properties": {}}}},
]

def call(model, messages, tools=None, tool_choice=None, timeout=90):
    body = {"model": model, "messages": messages, "temperature": 0}
    if tools: body["tools"] = tools
    if tool_choice: body["tool_choice"] = tool_choice
    req = urllib.request.Request(
        f"{BASE}/chat/completions",
        data=json.dumps(body).encode(),
        headers={"Authorization": f"Bearer {KEY}", "Content-Type": "application/json"},
    )
    t0 = time.time()
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return json.load(r), time.time() - t0, None
    except urllib.error.HTTPError as e:
        return None, time.time() - t0, f"HTTP {e.code}: {e.read().decode()[:300]}"
    except Exception as e:
        return None, time.time() - t0, f"{type(e).__name__}: {e}"

def tool_calls_of(resp):
    try: return resp["choices"][0]["message"].get("tool_calls") or []
    except Exception: return []

def content_of(resp):
    try: return (resp["choices"][0]["message"].get("content") or "").strip()
    except Exception: return ""

# --- the four checks ------------------------------------------------------

def t1_emits(model):
    """Does it call a tool at all, with valid JSON arguments?"""
    resp, dt, err = call(model, [
        {"role": "system", "content": "You are a Kubernetes SRE assistant. Use the tools available to you."},
        {"role": "user", "content": "Are there any errors in the checkout service in the last 6 hours?"},
    ], TOOLS)
    if err: return False, err, dt
    tc = tool_calls_of(resp)
    if not tc: return False, f"no tool_calls (said: {content_of(resp)[:90]!r})", dt
    fn = tc[0].get("function", {})
    if fn.get("name") != "query_logs": return False, f"called {fn.get('name')!r}", dt
    try:
        args = json.loads(fn.get("arguments") or "")
    except Exception as e:
        return False, f"arguments not valid JSON: {e}", dt
    if "query" not in args: return False, f"missing 'query' in {args}", dt
    return True, f"query_logs({json.dumps(args)[:70]})", dt

def t2_roundtrip(model):
    """Does it accept a tool result back and answer coherently? (the loop)"""
    msgs = [
        {"role": "system", "content": "You are a Kubernetes SRE assistant. Use the tools available to you."},
        {"role": "user", "content": "Are there any errors in the checkout service in the last 6 hours?"},
    ]
    resp, dt, err = call(model, msgs, TOOLS)
    if err: return False, err, dt
    tc = tool_calls_of(resp)
    if not tc: return False, "no tool_calls on first turn", dt
    msgs.append(resp["choices"][0]["message"])
    for c in tc:
        msgs.append({"role": "tool", "tool_call_id": c.get("id"),
                     "name": c.get("function", {}).get("name"),
                     "content": '{"matches": 412, "top_error": "502 upstream timeout", "first_seen": "2026-09-09T14:20:00Z"}'})
    resp2, dt2, err2 = call(model, msgs, TOOLS)
    if err2: return False, f"second turn: {err2}", dt + dt2
    out = content_of(resp2)
    if not out: return False, "empty answer on second turn", dt + dt2
    if "412" not in out and "502" not in out:
        return False, f"ignored tool result: {out[:90]!r}", dt + dt2
    return True, out[:80].replace("\n", " "), dt + dt2

def t3_multi(model):
    """Can it sequence/parallelise more than one tool?"""
    resp, dt, err = call(model, [
        {"role": "system", "content": "You are a Kubernetes SRE assistant. Use the tools available to you."},
        {"role": "user", "content": "Which services exist, and which of them logged errors in the last 24 hours?"},
    ], TOOLS)
    if err: return False, err, dt
    tc = tool_calls_of(resp)
    if not tc: return False, "no tool_calls", dt
    names = [c.get("function", {}).get("name") for c in tc]
    if "list_services" not in names:
        return False, f"did not reach for list_services (called {names})", dt
    return True, f"{len(tc)} call(s): {names}", dt

def t4_restraint(model):
    """Does it avoid calling tools when the question needs none?"""
    resp, dt, err = call(model, [
        {"role": "system", "content": "You are a Kubernetes SRE assistant. Use the tools available to you."},
        {"role": "user", "content": "In one sentence, what does the acronym SRE stand for?"},
    ], TOOLS)
    if err: return False, err, dt
    tc = tool_calls_of(resp)
    if tc: return False, f"called {[c.get('function',{}).get('name') for c in tc]} unnecessarily", dt
    if not content_of(resp): return False, "empty answer", dt
    return True, content_of(resp)[:70].replace("\n", " "), dt

CHECKS = [
    ("emits tool_calls", t1_emits),
    ("tool-result loop", t2_roundtrip),
    ("multi-tool",       t3_multi),
    ("restraint",        t4_restraint),
]

def main():
    models = sys.argv[1:]
    if not models:
        req = urllib.request.Request(f"{BASE}/models", headers={"Authorization": f"Bearer {KEY}"})
        with urllib.request.urlopen(req, timeout=30) as r:
            models = [m["id"] for m in json.load(r).get("data", [])
                      if "embed" not in m["id"].lower()]
    print(f"\n{B}relax.ai tool-calling probe{X}  {D}{BASE}{X}\n")
    results = {}
    for m in models:
        print(f"{B}{m}{X}")
        passed = 0
        for label, fn in CHECKS:
            try:
                good, detail, dt = fn(m)
            except Exception as e:
                good, detail, dt = False, f"probe error: {type(e).__name__}: {e}", 0.0
            mark = f"{G}pass{X}" if good else f"{R}FAIL{X}"
            passed += good
            print(f"  {mark}  {label:<18} {D}{dt:5.1f}s{X}  {detail}")
        results[m] = passed
        print()
    print(f"{B}Summary{X}  (kagent needs the first two, ideally all four)")
    for m, p in sorted(results.items(), key=lambda kv: -kv[1]):
        c = G if p == 4 else (Y if p >= 2 else R)
        print(f"  {c}{p}/4{X}  {m}")
    print()
    best = [m for m, p in results.items() if p == 4]
    if best: print(f"{G}Recommended RELAX_MODEL={best[0]}{X}\n")
    elif any(p >= 2 for p in results.values()): print(f"{Y}No model passed all four — see notes above.{X}\n")
    else: print(f"{R}No model is usable for kagent. The workshop design needs to change.{X}\n")

main()
