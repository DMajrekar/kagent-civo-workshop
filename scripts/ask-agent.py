#!/usr/bin/env python3
"""Ask a kagent agent a question and print its answer.

kagent agents speak A2A (JSON-RPC over HTTP). This is the smallest client that
does something useful with one, and it is what the workshop uses so attendees
can talk to their agent from a terminal instead of only through the UI.

  ./scripts/ask-agent.py http://127.0.0.1:8080 "what is running in kube-system?"
"""
import argparse, json, sys, time, urllib.error, urllib.request, uuid

G, R, Y, D, B, X = "\033[32m", "\033[31m", "\033[33m", "\033[2m", "\033[1m", "\033[0m"


def rpc(url, method, params, timeout):
    body = json.dumps({"jsonrpc": "2.0", "id": str(uuid.uuid4()),
                       "method": method, "params": params}).encode()
    req = urllib.request.Request(url, data=body, method="POST",
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.load(r)


def texts(obj, out):
    """Pull every text part out of an A2A result, whatever shape it arrived in."""
    if isinstance(obj, dict):
        if obj.get("kind") == "text" and "text" in obj:
            out.append(obj["text"])
        elif "text" in obj and isinstance(obj["text"], str) and "parts" not in obj:
            out.append(obj["text"])
        for v in obj.values():
            texts(v, out)
    elif isinstance(obj, list):
        for v in obj:
            texts(v, out)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("url")
    ap.add_argument("question")
    ap.add_argument("--timeout", type=int, default=300)
    ap.add_argument("--raw", action="store_true", help="print the whole JSON result")
    a = ap.parse_args()

    card = None
    try:
        with urllib.request.urlopen(f"{a.url}/.well-known/agent-card.json", timeout=30) as r:
            card = json.load(r)
        print(f"{D}agent:{X} {B}{card.get('name','?')}{X} — {card.get('description','')[:70]}")
    except Exception:
        print(f"{Y}could not read the agent card; trying anyway{X}")

    print(f"{D}asking:{X} {a.question}\n")
    t0 = time.time()
    try:
        resp = rpc(a.url, "message/send", {
            "message": {
                "role": "user",
                "parts": [{"kind": "text", "text": a.question}],
                "messageId": str(uuid.uuid4()),
                "kind": "message",
            }
        }, a.timeout)
    except urllib.error.HTTPError as e:
        print(f"{R}HTTP {e.code}: {e.read().decode('utf-8','replace')[:400]}{X}")
        sys.exit(1)
    except Exception as e:
        print(f"{R}{type(e).__name__}: {e}{X}")
        sys.exit(1)

    if "error" in resp:
        print(f"{R}agent returned an error:{X}")
        print(json.dumps(resp["error"], indent=2)[:1500])
        sys.exit(1)

    if a.raw:
        print(json.dumps(resp.get("result"), indent=2)[:8000])
        return

    parts = [t for t in texts(resp.get("result"), []) if t.strip()]
    # The final assistant turn is what a human wants; earlier parts are the
    # agent's intermediate tool chatter.
    if parts:
        print(parts[-1].strip())
    else:
        print(f"{Y}no text in the reply — rerun with --raw to see the envelope{X}")
        sys.exit(1)
    print(f"\n{D}({time.time()-t0:.1f}s){X}")


main()
