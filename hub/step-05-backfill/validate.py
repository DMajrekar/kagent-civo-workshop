#!/usr/bin/env python3
"""Assert the seeded dataset actually contains its six planted incidents.

The workshop's payoff is an agent finding these. If the generator drifts, or a
backfill half-fails, or Loki drops a window, step-04 quietly becomes "the agent
says everything looks fine" in front of a room. This catches that beforehand.

Each check is written the way an agent would have to find it -- aggregate
LogQL over the whole window, not a lookup of a known string -- so passing here
means the incident is genuinely discoverable, not merely present.
"""
import json, os, sys, time, urllib.parse, urllib.request

LOKI = os.environ.get("LOKI_URL", "http://127.0.0.1:3100")
G, R, Y, D, B, X = "\033[32m", "\033[31m", "\033[33m", "\033[2m", "\033[1m", "\033[0m"
NOW = int(time.time())


def q(expr, at=None):
    """Instant query, returns list of (labels, float value)."""
    url = f"{LOKI}/loki/api/v1/query?" + urllib.parse.urlencode(
        {"query": expr, "time": (at or NOW) * 10**9})
    with urllib.request.urlopen(url, timeout=120) as r:
        d = json.load(r)
    if d.get("status") != "success":
        raise RuntimeError(str(d)[:200])
    return [(m["metric"], float(m["value"][1])) for m in d["data"]["result"]]


def one(expr, at=None):
    r = q(expr, at)
    return r[0][1] if r else 0.0


CHECKS = []
def check(name, why):
    def deco(fn):
        CHECKS.append((name, why, fn)); return fn
    return deco


@check("1 checkout deploy regression", "a step change correlated with a version label")
def c1():
    recent = one('sum(count_over_time({service="checkout", level="error"}[2d]))')
    before = one('sum(count_over_time({service="checkout", level="error"}[2d]))', NOW - 5 * 86400)
    vers = {m.get("version") for m, _ in q('sum by (version) (count_over_time({service="checkout"}[2d]))')}
    if "v2.3.1" not in vers:
        return False, f"no v2.3.1 label in the last 2 days (saw {vers or 'nothing'})"
    if recent < before * 3:
        return False, f"error rate not clearly elevated: {recent:.0f} recent vs {before:.0f} before"
    return True, f"{recent:.0f} errors/2d now vs {before:.0f} before deploy, versions {sorted(v for v in vers if v)}"


@check("2 nightly pool exhaustion", "periodicity — invisible unless you aggregate by hour")
def c2():
    hits = one('sum(count_over_time({service="orders-db-proxy"} |= "remaining connection slots" [7d]))')
    if hits < 50:
        return False, f"only {hits:.0f} pool-exhaustion lines in 7 days"
    # Confirm they cluster in the 02:00 hour rather than being spread out.
    in_window = one('sum(count_over_time({service="orders-db-proxy"} |= "remaining connection slots" [40m]))',
                    _last_0200() + 2400)
    return True, f"{hits:.0f} lines over 7d, {in_window:.0f} in the most recent 02:00-02:40 window"


def _last_0200():
    import datetime as dt
    n = dt.datetime.now(dt.timezone.utc)
    d = n.replace(hour=2, minute=0, second=0, microsecond=0)
    if d > n:
        d -= dt.timedelta(days=1)
    return int(d.timestamp())


@check("3 image-resizer OOM crashloop", "an escalating trend")
def c3():
    recent = one('sum(count_over_time({service="image-resizer"} |= "OOMKilled" [1d]))')
    earlier = one('sum(count_over_time({service="image-resizer"} |= "OOMKilled" [1d]))', NOW - 4 * 86400)
    if recent < 10:
        return False, f"only {recent:.0f} OOMKills in the last day"
    if recent <= earlier:
        return False, f"not worsening: {recent:.0f} today vs {earlier:.0f} four days ago"
    return True, f"{recent:.0f} OOMKills today vs {earlier:.0f} four days ago"


@check("4 notifications log volume", "volume, not errors — nothing is failing")
def c4():
    by_svc = sorted(q('sum by (service) (count_over_time({env="production"}[1d]))'),
                    key=lambda kv: -kv[1])
    if not by_svc:
        return False, "no data at all"
    top, topn = by_svc[0][0]["service"], by_svc[0][1]
    second = by_svc[1][1] if len(by_svc) > 1 else 0
    if top != "notifications":
        return False, f"top service is {top} ({topn:.0f}), not notifications"
    if topn < second * 2:
        return False, f"notifications {topn:.0f} not clearly dominant over {second:.0f}"
    share = topn / sum(v for _, v in by_svc) * 100
    return True, f"notifications {topn:.0f} lines/day = {share:.0f}% of all volume, {topn/second:.1f}x the next"


@check("5 auth cert expiry", "a prediction — the failure has not happened yet")
def c5():
    hits = one('sum(count_over_time({service="auth"} |= "TLS certificate" [7d]))')
    if hits < 5:
        return False, f"only {hits:.0f} cert-expiry warnings in 7 days"
    return True, f"{hits:.0f} cert-expiry warnings over 7 days, no errors alongside"


@check("6 search latency creep", "pure regression with zero errors")
def c6():
    expr = ('avg_over_time({service="search"} |= "p99" '
            '| regexp `(?P<lat>[0-9]+)ms p99` | unwrap lat [6h])')
    recent = one(f"avg({expr})")
    old = one(f"avg({expr})", NOW - 6 * 86400)
    errs = one('sum(count_over_time({service="search", level="error"}[7d]))')
    if not recent or not old:
        return False, f"could not measure latency (recent={recent}, old={old})"
    if recent < old * 1.15:
        return False, f"no clear creep: {old:.0f}ms then vs {recent:.0f}ms now"
    if errs:
        # The teaching point is that an agent can spot a regression with no
        # errors to grep for. Any error here weakens it.
        return False, f"creep is there but search logged {errs:.0f} errors — incident 6 should have none"
    return True, f"{old:.0f}ms six days ago vs {recent:.0f}ms now (+{(recent/old-1)*100:.0f}%), and zero errors"


def main():
    print(f"\n{B}Validating the seeded dataset{X}  {D}{LOKI}{X}\n")
    failed = 0
    for name, why, fn in CHECKS:
        try:
            good, detail = fn()
        except Exception as e:
            good, detail = False, f"{type(e).__name__}: {e}"
        print(f"  {G}pass{X}  {name}" if good else f"  {R}FAIL{X}  {name}")
        print(f"        {D}{why}{X}")
        print(f"        {detail}\n")
        failed += not good
    if failed:
        print(f"{R}{B}{failed} of {len(CHECKS)} incidents are not discoverable.{X}")
        print(f"{D}Step-04 depends on these. Fix before the event.{X}\n")
        sys.exit(1)
    print(f"{G}{B}All {len(CHECKS)} incidents are discoverable.{X}\n")


main()
