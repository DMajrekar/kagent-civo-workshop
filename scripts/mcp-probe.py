#!/usr/bin/env python3
"""Speak MCP to an endpoint and report what it offers.

Used to prove the hub's MCP endpoint works before an agent depends on it, and
again from an attendee cluster to prove the path from there. A curl returning
200 is not evidence: MCP is a JSON-RPC handshake over Streamable HTTP, and a
proxy can happily return 200 for a session it has actually broken.

  ./scripts/mcp-probe.py <url> [--token TOKEN] [--call TOOL --args JSON]
"""
import argparse, json, os, sys, urllib.error, urllib.request

G, R, Y, D, B, X = "\033[32m", "\033[31m", "\033[33m", "\033[2m", "\033[1m", "\033[0m"


class MCP:
    def __init__(self, url, token=None):
        self.url, self.token, self.session, self._id = url, token, None, 0

    def _post(self, method, params=None, notify=False):
        self._id += 1
        payload = {"jsonrpc": "2.0", "method": method}
        if not notify:
            payload["id"] = self._id
        if params is not None:
            payload["params"] = params
        headers = {
            "Content-Type": "application/json",
            # Streamable HTTP servers may reply with either, and will 406 if
            # the client does not say it accepts both.
            "Accept": "application/json, text/event-stream",
        }
        if self.token:
            headers["Authorization"] = f"Bearer {self.token}"
        if self.session:
            headers["Mcp-Session-Id"] = self.session
        req = urllib.request.Request(self.url, data=json.dumps(payload).encode(),
                                     headers=headers, method="POST")
        with urllib.request.urlopen(req, timeout=60) as r:
            sid = r.headers.get("Mcp-Session-Id")
            if sid:
                self.session = sid
            raw = r.read().decode("utf-8", "replace")
        if not raw.strip():
            return None
        # A Streamable HTTP reply may be an SSE stream; take the data frames.
        if raw.lstrip().startswith("event:") or raw.lstrip().startswith("data:"):
            for line in raw.splitlines():
                if line.startswith("data:"):
                    body = json.loads(line[5:].strip())
                    if "error" in body:
                        raise RuntimeError(body["error"])
                    return body.get("result")
            return None
        body = json.loads(raw)
        if "error" in body:
            raise RuntimeError(body["error"])
        return body.get("result")

    def initialize(self):
        r = self._post("initialize", {
            "protocolVersion": "2025-06-18",
            "capabilities": {},
            "clientInfo": {"name": "workshop-mcp-probe", "version": "1.0"},
        })
        self._post("notifications/initialized", notify=True)
        return r

    def tools(self):
        return (self._post("tools/list", {}) or {}).get("tools", [])

    def call(self, name, args):
        return self._post("tools/call", {"name": name, "arguments": args})


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("url")
    ap.add_argument("--token")
    # Lets a caller pass the token without putting it in a displayed command.
    ap.add_argument("--token-env", help="read the token from this env var instead")
    ap.add_argument("--call")
    ap.add_argument("--args", default="{}")
    ap.add_argument("--quiet", action="store_true")
    a = ap.parse_args()

    token = os.environ.get(a.token_env) if a.token_env else a.token
    m = MCP(a.url, token)
    try:
        info = m.initialize()
    except urllib.error.HTTPError as e:
        print(f"{R}handshake failed: HTTP {e.code} {e.reason}{X}")
        print(f"{D}{e.read().decode('utf-8','replace')[:300]}{X}")
        sys.exit(1)
    except Exception as e:
        print(f"{R}handshake failed: {type(e).__name__}: {e}{X}")
        sys.exit(1)

    srv = (info or {}).get("serverInfo", {})
    print(f"{G}connected{X} to {B}{srv.get('name','?')}{X} {srv.get('version','')}"
          f"  {D}session={m.session or 'none'}{X}")

    tools = m.tools()
    print(f"{B}{len(tools)} tools{X}")
    if not a.quiet:
        for t in sorted(tools, key=lambda t: t["name"]):
            desc = (t.get("description") or "").split("\n")[0][:78]
            print(f"  {t['name']:<34} {D}{desc}{X}")

    if a.call:
        print(f"\n{B}calling {a.call}{X} {D}{a.args}{X}")
        res = m.call(a.call, json.loads(a.args))
        for c in (res or {}).get("content", []):
            print(c.get("text", json.dumps(c))[:3000])
        if (res or {}).get("isError"):
            print(f"{R}tool reported an error{X}")
            sys.exit(1)


main()
