#!/usr/bin/env python3
"""Ask the agent for a report and post it to the wall.

Runs as a CronJob in the attendee's cluster. Two moving parts: an A2A call to
the agent, and an HTTP POST of whatever it says. If no webhook is configured it
prints the report instead, so the job is still useful on its own.
"""
import json, os, sys, time, urllib.error, urllib.request, uuid

AGENT = os.environ.get("AGENT_URL", "http://log-detective.kagent.svc.cluster.local:8080")
HOOK = os.environ.get("REPORT_WEBHOOK_URL", "").strip()
TIMEOUT = int(os.environ.get("TIMEOUT", "600"))
PROMPT = os.environ.get("PROMPT") or (
    "Write a short operations report on the last 24 hours of production logs.\n\n"
    "Cover, in this order:\n"
    "1. Total errors in the last 24h, and which services they came from.\n"
    "2. Anything that got measurably worse compared with the previous days.\n"
    "3. Anything recurring or scheduled.\n"
    "4. One thing worth looking at first, and why.\n\n"
    "Be specific: name services, give counts. Keep it under 250 words. "
    "If something looks fine, say so rather than padding."
)


def texts(obj, out):
    if isinstance(obj, dict):
        if obj.get("kind") == "text" and "text" in obj:
            out.append(obj["text"])
        elif isinstance(obj.get("text"), str) and "parts" not in obj:
            out.append(obj["text"])
        for v in obj.values():
            texts(v, out)
    elif isinstance(obj, list):
        for v in obj:
            texts(v, out)
    return out


def ask():
    body = json.dumps({
        "jsonrpc": "2.0", "id": str(uuid.uuid4()), "method": "message/send",
        "params": {"message": {
            "role": "user",
            "parts": [{"kind": "text", "text": PROMPT}],
            "messageId": str(uuid.uuid4()), "kind": "message",
        }},
    }).encode()
    req = urllib.request.Request(AGENT, data=body, method="POST",
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
        resp = json.load(r)
    if "error" in resp:
        raise RuntimeError(json.dumps(resp["error"])[:400])
    parts = [t for t in texts(resp.get("result"), []) if t.strip()]
    if not parts:
        raise RuntimeError("the agent returned no text")
    return parts[-1].strip()


def post(text):
    stamp = time.strftime("%Y-%m-%d %H:%M UTC", time.gmtime())
    payload = json.dumps({"text": f"Daily report — {stamp}\n\n{text}"}).encode()
    req = urllib.request.Request(HOOK, data=payload, method="POST",
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return r.status


def main():
    print(f"asking {AGENT}", flush=True)
    t0 = time.time()
    try:
        report = ask()
    except urllib.error.HTTPError as e:
        print(f"agent HTTP {e.code}: {e.read().decode('utf-8','replace')[:300]}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"agent call failed: {type(e).__name__}: {e}", file=sys.stderr)
        sys.exit(1)
    print(f"got {len(report)} chars in {time.time()-t0:.0f}s\n", flush=True)
    print(report, flush=True)

    if not HOOK:
        print("\nREPORT_WEBHOOK_URL is not set — printed above instead of posting.",
              flush=True)
        return
    try:
        print(f"\nposting to {HOOK} -> HTTP {post(report)}", flush=True)
    except Exception as e:
        # The report is already in the logs, so this is not worth failing the
        # job over -- but it must be loud, or a silently broken webhook looks
        # exactly like an agent that stopped working.
        print(f"\nWEBHOOK POST FAILED: {type(e).__name__}: {e}", file=sys.stderr)
        sys.exit(2)


main()
