#!/usr/bin/env python3
"""Count entries in a Loki query_range response matching $MARKER.

Reads the response body from $LOKI_BODY rather than stdin: the caller is a
bash function that already has the body in a variable, and chaining two stdin
redirections silently feeds the wrong one to the interpreter.

Prints a count, or a tagged error the caller can distinguish from "zero hits" —
a query that errors and a query that legitimately finds nothing look identical
otherwise, and that difference is worth an afternoon.
"""
import json, os, sys

body = os.environ.get("LOKI_BODY", "")
marker = os.environ.get("MARKER", "")
try:
    d = json.loads(body)
except Exception as e:
    print(f"BAD_JSON:{e}"); sys.exit(0)
if d.get("status") != "success":
    print(f"LOKI_ERROR:{str(d)[:200]}"); sys.exit(0)
print(sum(1 for r in d["data"]["result"] for _, line in r["values"] if line == marker))
