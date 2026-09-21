#!/usr/bin/env python3
"""Log generator for the workshop hub.

Simulates a small e-commerce platform whose services misbehave in specific,
discoverable ways (see docs/INCIDENTS.md). One script does two jobs:

  --backfill --days 7   write history with past timestamps, then exit
  --live                write continuously at wall-clock time

Both share the same emit path, so backfilled history and live traffic are
identical by construction -- there is no seam for an agent to notice, and no
second code path to keep in sync.

Determinism: seeded from --seed, so a re-seed on the morning of the event
tells exactly the same story as the rehearsal did.
"""
import argparse, json, math, os, random, sys, time
import urllib.error
import urllib.request
from datetime import datetime, timezone

LOKI = os.environ.get("LOKI_URL", "http://loki.observability.svc.cluster.local:3100")

# ---------------------------------------------------------------- the fleet

SERVICES = {
    "web":             dict(rate=40, err=0.004),
    "api-gateway":     dict(rate=35, err=0.006),
    "checkout":        dict(rate=18, err=0.005),
    "orders-db-proxy": dict(rate=12, err=0.003),
    "search":          dict(rate=22, err=0.0),    # incident 6: degrades with zero errors
    "image-resizer":   dict(rate=8,  err=0.004),
    "notifications":   dict(rate=10, err=0.003),
    "auth":            dict(rate=15, err=0.004),
}

INFO = {
    "web": ["GET / 200 {ms}ms", "GET /product/{id} 200 {ms}ms", "GET /cart 200 {ms}ms"],
    "api-gateway": ["routed {method} /v1/{path} -> {svc} 200 {ms}ms", "health check ok"],
    "checkout": ["order {id} accepted total={amt}", "payment authorised order={id} {ms}ms",
                 "cart {id} converted"],
    "orders-db-proxy": ["query orders.select {ms}ms rows={n}", "pool acquired conn={n}/50",
                        "transaction committed {ms}ms"],
    "search": ["query q={q!r} hits={n} {ms}ms", "index refreshed docs={n}"],
    "image-resizer": ["resized {id} 2048x2048->512x512 {ms}ms", "cache hit {id}"],
    "notifications": ["queued email to user={id}", "sent push user={id} {ms}ms",
                      "template rendered {id}"],
    "auth": ["token issued user={id} {ms}ms", "session refreshed user={id}",
             "login ok user={id}"],
}

WARN = {
    "web": ["slow response GET /product/{id} {ms}ms"],
    "api-gateway": ["upstream {svc} slow {ms}ms", "retrying {method} /v1/{path} attempt=2"],
    "checkout": ["payment retry order={id} attempt=2"],
    "orders-db-proxy": ["pool usage high conn={n}/50", "slow query orders.select {ms}ms"],
    "search": ["query latency above target {ms}ms q={q!r}"],
    "image-resizer": ["memory usage high {n}MB of 512MB"],
    "notifications": ["delivery delayed user={id} queue_depth={n}"],
    "auth": ["token near expiry user={id}"],
}

ERR = {
    "web": ["GET /product/{id} 500 upstream error"],
    "api-gateway": ["upstream {svc} returned 502 after {ms}ms"],
    "checkout": ["payment declined order={id} code=card_declined"],
    "orders-db-proxy": ["query failed: deadlock detected"],
    "search": ["query failed q={q!r}: shard unavailable"],
    "image-resizer": ["resize failed {id}: source corrupt"],
    "notifications": ["delivery failed user={id}: smtp timeout"],
    "auth": ["login failed user={id}: invalid credentials"],
}

QUERIES = ["red shoes", "laptop stand", "usb-c cable", "winter coat", "desk lamp",
           "running socks", "coffee beans", "phone case"]
PATHS = ["orders", "products", "users", "cart", "search"]


def diurnal(ts):
    """Traffic multiplier: busy 09:00-22:00 UTC, quiet overnight, weekend dip."""
    dt = datetime.fromtimestamp(ts, timezone.utc)
    h = dt.hour + dt.minute / 60.0
    base = 0.35 + 0.65 * max(0.0, math.sin((h - 5) / 24.0 * 2 * math.pi))
    if dt.weekday() >= 5:
        base *= 0.65
    return base


def fmt(rng, tpl):
    return tpl.format(
        id=rng.randint(10000, 99999), ms=rng.randint(3, 400),
        n=rng.randint(1, 50), amt=f"{rng.uniform(5, 400):.2f}",
        q=rng.choice(QUERIES), svc=rng.choice(list(SERVICES)),
        method=rng.choice(["GET", "POST", "PUT"]), path=rng.choice(PATHS),
    )


# ------------------------------------------------------------- the incidents
#
# Each returns extra (level, message, labels) entries for a given service and
# timestamp, on top of the baseline hum. Keyed off `age_days` -- how long
# before the end of the window this moment is -- so the story stays anchored to
# "now" no matter when the dataset is seeded.

def incidents(rng, svc, ts, age_days, end_ts):
    out = []
    dt = datetime.fromtimestamp(ts, timezone.utc)

    # 1. checkout: error rate steps up after a deploy 4 days ago, never recovers
    if svc == "checkout":
        deployed = age_days <= 4.0
        ver = "v2.3.1" if deployed else "v2.3.0"
        if deployed and abs(age_days - 4.0) < 0.005:
            out.append(("info", "starting checkout v2.3.1 (build 8812)", {"version": ver}))
        # Has to be a step change you cannot miss. At 8.5% the post-deploy rate
        # was only ~2.6x baseline, which passed or failed depending on how long
        # live generation had been topping up the recent window -- too fragile
        # for the incident the session opens with.
        if deployed and rng.random() < 0.22:
            out.append(("error", fmt(rng, "payment gateway call failed order={id}: 502 upstream timeout"),
                        {"version": ver}))
        if deployed and rng.random() < 0.08:
            out.append(("warn", fmt(rng, "payment gateway slow order={id} {ms}ms (threshold 2000ms)"),
                        {"version": ver}))
        return [(lvl, msg, {**lbl, "version": ver}) for lvl, msg, lbl in out] or \
               [("__label__", "", {"version": ver})]

    # 2. orders-db-proxy: connection pool exhausted nightly 02:00-02:40.
    # This has to be *loud*. A handful of errors an hour disappears into the
    # baseline, and an agent aggregating by hour will honestly report that it
    # found no scheduled problem -- which is exactly what happened at first.
    if svc == "orders-db-proxy" and dt.hour == 2 and dt.minute < 40:
        if dt.minute == 0:
            out.append(("info", "nightly reconciliation batch started (job=orders-reconcile)", {}))
        for _ in range(rng.randint(8, 16)):
            out.append(("error", "FATAL: remaining connection slots are reserved for superuser connections", {}))
        for _ in range(rng.randint(4, 9)):
            out.append(("warn", f"pool exhausted conn=50/50 waiters={rng.randint(3,40)}", {}))
        if rng.random() < 0.3:
            out.append(("error", f"query failed: timeout acquiring connection after {rng.randint(5,30)}s", {}))
        if dt.minute == 39:
            out.append(("info", "nightly reconciliation batch finished", {}))

    # 3. image-resizer: OOMKill crashloop starting 2 days ago, worsening
    if svc == "image-resizer" and age_days <= 2.0:
        severity = (2.0 - age_days) / 2.0            # 0 -> 1 as it approaches now
        if rng.random() < 0.05 + 0.25 * severity:
            out.append(("warn", f"memory usage high {rng.randint(460, 511)}MB of 512MB", {}))
        if rng.random() < 0.01 + 0.06 * severity:
            out.append(("error", "container killed: OOMKilled (exit 137)", {}))
            out.append(("info", "starting image-resizer worker pool=4", {}))

    # 4. notifications: debug logging left on in prod -- harmless, and by far
    # the largest consumer of log volume. Needs to dominate clearly enough that
    # "where is our log spend going" has one obvious answer.
    if svc == "notifications":
        for _ in range(rng.randint(45, 75)):
            out.append(("debug", fmt(rng, "template ctx={{'user': {id}, 'locale': 'en-GB', 'items': {n}}}"), {}))

    # 5. auth: TLS cert expiry, counting down. Nothing is failing -- this is a
    # prediction, and it competes for the agent's attention against services
    # that are actively on fire. It needs to be frequent enough to notice.
    if svc == "auth" and age_days <= 5.0:
        days_left = int(9 + age_days)
        if rng.random() < 0.06:
            out.append(("warn", f"TLS certificate for auth.internal expires in {days_left} days "
                                f"(notAfter=2026-09-30T00:00:00Z) -- renew before expiry", {}))
        # An escalating note as the deadline closes, so a time-ordered read
        # shows the countdown rather than a flat repeated line.
        if days_left <= 10 and rng.random() < 0.03:
            out.append(("warn", f"certificate renewal not yet performed for auth.internal; "
                                f"{days_left} days remain before clients fail TLS handshake", {}))

    # 6. search: p99 latency creeping up ~8%/day, no errors at all
    if svc == "search":
        creep = 1.0 + 0.08 * max(0.0, 7.0 - age_days)
        if rng.random() < 0.12:
            lat = int(rng.randint(80, 180) * creep)
            lvl = "warn" if lat > 400 else "info"
            out.append((lvl, f"query completed q={rng.choice(QUERIES)!r} {lat}ms p99={int(lat*1.4)}ms", {}))

    return out


def gen_window(rng, start_ts, end_ts, step, on_batch, batch_size=2000):
    """Walk [start_ts, end_ts) in `step` seconds, emitting into Loki streams."""
    streams = {}
    pending = 0
    ts = start_ts
    while ts < end_ts:
        mult = diurnal(ts)
        age_days = (end_ts - ts) / 86400.0
        for svc, cfg in SERVICES.items():
            n = max(0, int(rng.gauss(cfg["rate"] * mult * (step / 60.0), 1.5)))
            extra_labels = {}
            for lvl, msg, lbl in incidents(rng, svc, ts, age_days, end_ts):
                if lvl == "__label__":
                    extra_labels.update(lbl); continue
                key = (svc, lvl, tuple(sorted({**lbl, **extra_labels}.items())))
                streams.setdefault(key, []).append(
                    (str(int(ts * 1e9) + rng.randint(0, 999999)), msg))
                pending += 1
            for _ in range(n):
                r = rng.random()
                if r < cfg["err"]:
                    lvl, pool = "error", ERR[svc]
                elif r < cfg["err"] + 0.04:
                    lvl, pool = "warn", WARN[svc]
                else:
                    lvl, pool = "info", INFO[svc]
                key = (svc, lvl, tuple(sorted(extra_labels.items())))
                streams.setdefault(key, []).append(
                    (str(int(ts * 1e9) + rng.randint(0, 999999)), fmt(rng, rng.choice(pool))))
                pending += 1
        if pending >= batch_size:
            on_batch(streams); streams = {}; pending = 0
        ts += step
    if streams:
        on_batch(streams)


REJECTED = {"batches": 0, "sample": ""}


def push(streams, retries=5):
    payload = {"streams": [
        {"stream": {"service": svc, "level": lvl, "env": "production", **dict(extra)},
         "values": sorted(vals, key=lambda v: int(v[0]))}
        for (svc, lvl, extra), vals in streams.items()
    ]}
    body = json.dumps(payload).encode()
    for attempt in range(retries):
        req = urllib.request.Request(f"{LOKI}/loki/api/v1/push", data=body,
                                     headers={"Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                if r.status in (200, 204):
                    return sum(len(v) for v in streams.values())
        except urllib.error.HTTPError as e:
            detail = e.read().decode("utf-8", "replace")[:300]
            if e.code == 400:
                # Not retriable, and always structural: an out-of-order entry,
                # a stream limit, or a malformed label. Say which.
                REJECTED["batches"] += 1
                if not REJECTED["sample"]:
                    REJECTED["sample"] = detail
                    print(f"push rejected (400): {detail}", file=sys.stderr)
                return 0
            if attempt == retries - 1:
                print(f"push failed after {retries} attempts: {e}: {detail}", file=sys.stderr)
                return 0
        except Exception as e:
            if attempt == retries - 1:
                print(f"push failed after {retries} attempts: {e}", file=sys.stderr)
                return 0
            time.sleep(2 ** attempt)
    return 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--backfill", action="store_true")
    ap.add_argument("--live", action="store_true")
    ap.add_argument("--days", type=float, default=7.0)
    ap.add_argument("--step", type=int, default=60, help="simulated seconds per tick")
    ap.add_argument("--seed", type=int, default=20260922)
    args = ap.parse_args()
    rng = random.Random(args.seed)

    if args.backfill:
        end = time.time()
        start = end - args.days * 86400
        total = 0
        t0 = time.time()
        tty = sys.stdout.isatty()
        last = [0.0]
        def on_batch(s):
            nonlocal total
            total += push(s)
            if tty:
                print(f"\r  pushed {total:,} lines", end="", flush=True)
            elif time.time() - last[0] > 5:
                last[0] = time.time()
                print(f"  pushed {total:,} lines", flush=True)
        gen_window(rng, start, end, args.step, on_batch)
        print(f"\n  backfilled {total:,} lines over {args.days} days in {time.time()-t0:.0f}s")
        if REJECTED["batches"]:
            # Exit non-zero so the Job fails and hub-05 stops, rather than
            # handing a dataset with holes to a validator that may not notice.
            print(f"\n  {REJECTED['batches']} batch(es) were REJECTED — this dataset has holes.",
                  file=sys.stderr)
            print(f"  first rejection: {REJECTED['sample']}", file=sys.stderr)
            print("  most likely something else was writing to the same streams.",
                  file=sys.stderr)
            sys.exit(1)
        return

    if args.live:
        print(f"live generation -> {LOKI}", flush=True)
        while True:
            now = time.time()
            gen_window(rng, now - 15, now, 15, push, batch_size=1)
            time.sleep(15)

    ap.error("pass --backfill or --live")


main()
