#!/usr/bin/env python3
"""Hammer the hub's MCP endpoint with N concurrent clients.

Everyone runs step-04 at the same time, so the interesting question is not
"does it work" but "does it work when the whole room asks at once". Each worker
does a full MCP handshake and then a realistic Loki query -- the same shape an
agent's tool call takes.

  ./scripts/loadtest-mcp.py <url> --token T --clients 50
"""
import argparse, json, statistics, sys, threading, time, urllib.error, urllib.request, uuid

G, R, Y, D, B, X = "\033[32m", "\033[31m", "\033[33m", "\033[2m", "\033[1m", "\033[0m"


def rpc(url, token, method, params, session=None, timeout=120):
    body = {"jsonrpc": "2.0", "method": method, "params": params}
    if method != "notifications/initialized":
        body["id"] = str(uuid.uuid4())
    headers = {"Content-Type": "application/json",
               "Accept": "application/json, text/event-stream",
               "Authorization": f"Bearer {token}"}
    if session:
        headers["Mcp-Session-Id"] = session
    req = urllib.request.Request(url, data=json.dumps(body).encode(), headers=headers)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        sid = r.headers.get("Mcp-Session-Id")
        raw = r.read().decode("utf-8", "replace")
    if raw.lstrip().startswith(("event:", "data:")):
        for line in raw.splitlines():
            if line.startswith("data:"):
                return json.loads(line[5:].strip()), sid
        return {}, sid
    return (json.loads(raw) if raw.strip() else {}), sid


# Light: discovery calls an agent makes while orienting itself.
LIGHT = [
    ("list_loki_label_values", {"datasourceUid": "workshop-loki", "labelName": "service"}),
    ("query_loki_stats", {"datasourceUid": "workshop-loki",
                          "logQL": '{env="production"}'}),
    ("query_loki_logs", {"datasourceUid": "workshop-loki",
                         "logQL": '{service="checkout", level="error"}',
                         "limit": 20}),
]

# Heavy: the aggregates an agent actually writes to answer "has anything got
# worse this week". These scan days of data and are the real load.
HEAVY = [
    ("query_loki_logs", {"datasourceUid": "workshop-loki",
                         "logQL": 'sum by (service) (count_over_time({env="production"}[24h]))',
                         "queryType": "instant"}),
    ("query_loki_logs", {"datasourceUid": "workshop-loki",
                         "logQL": 'sum by (service) (count_over_time({level="error"}[7d]))',
                         "queryType": "instant"}),
    ("query_loki_logs", {"datasourceUid": "workshop-loki",
                         "logQL": 'sum(count_over_time({service="notifications"}[7d]))',
                         "queryType": "instant"}),
]
QUERIES = LIGHT

RESULTS = []
LOCK = threading.Lock()


def worker(n, url, token, barrier):
    q_name, q_args = QUERIES[n % len(QUERIES)]
    barrier.wait()                      # everyone starts together, like the room does
    t0 = time.time()
    try:
        res, sid = rpc(url, token, "initialize",
                       {"protocolVersion": "2025-06-18", "capabilities": {},
                        "clientInfo": {"name": f"load-{n}", "version": "1"}})
        if "error" in res:
            raise RuntimeError(str(res["error"])[:120])
        try:
            rpc(url, token, "notifications/initialized", {}, sid)
        except Exception:
            pass
        res, _ = rpc(url, token, "tools/call",
                     {"name": q_name, "arguments": q_args}, sid)
        if "error" in res:
            raise RuntimeError(str(res["error"])[:120])
        if (res.get("result") or {}).get("isError"):
            txt = json.dumps(res["result"])[:120]
            raise RuntimeError(f"tool error: {txt}")
        ok, err = True, None
    except urllib.error.HTTPError as e:
        ok, err = False, f"HTTP {e.code}"
    except Exception as e:
        ok, err = False, f"{type(e).__name__}: {e}"[:140]
    dt = time.time() - t0
    with LOCK:
        RESULTS.append((ok, dt, err, q_name))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("url")
    ap.add_argument("--token", required=True)
    ap.add_argument("--clients", type=int, default=25)
    ap.add_argument("--heavy", action="store_true",
                    help="use the aggregate queries a real agent writes")
    a = ap.parse_args()
    global QUERIES
    QUERIES = HEAVY if a.heavy else LIGHT

    print(f"\n{B}MCP load test{X}  {D}{a.url}{X}")
    print(f"{a.clients} clients, all starting at once, "
          f"{'HEAVY aggregate' if a.heavy else 'light discovery'} queries\n")

    barrier = threading.Barrier(a.clients)
    threads = [threading.Thread(target=worker, args=(i, a.url, a.token, barrier))
               for i in range(a.clients)]
    t0 = time.time()
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    wall = time.time() - t0

    oks = [d for ok, d, _, _ in RESULTS if ok]
    bad = [(e, q) for ok, _, e, q in RESULTS if not ok]
    n = len(RESULTS)
    print(f"  {B}{len(oks)}/{n}{X} succeeded   wall clock {wall:.1f}s")
    if oks:
        s = sorted(oks)
        print(f"  latency  p50 {statistics.median(s):5.1f}s   "
              f"p95 {s[min(len(s) - 1, int(len(s) * 0.95))]:5.1f}s   "
              f"max {max(s):5.1f}s")
    if bad:
        print(f"\n  {R}{len(bad)} failures{X}")
        counts = {}
        for e, q in bad:
            counts[e] = counts.get(e, 0) + 1
        for e, c in sorted(counts.items(), key=lambda kv: -kv[1])[:6]:
            print(f"    {c:3d}x  {e}")
    print()
    if not bad and oks and max(oks) < 30:
        print(f"{G}Healthy at {a.clients} concurrent clients.{X}\n")
    elif not bad:
        print(f"{Y}No failures, but the slowest took {max(oks):.0f}s — "
              f"an agent doing ten of these would crawl.{X}\n")
    else:
        print(f"{R}Not healthy at {a.clients} concurrent clients.{X}\n")
        sys.exit(1)


main()
