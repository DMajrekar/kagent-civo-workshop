#!/usr/bin/env bash
# title: Give your agent seven days of production logs
source "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib.sh"

STATE="$REPO_ROOT/.state"
export KUBECONFIG="$STATE/workshop.kubeconfig"
[[ -f "$KUBECONFIG" ]] || { fail "no kubeconfig — run 'make step-02' first"; exit 1; }
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Attendees get these on their workshop card, in .env. The instructor running
# the whole thing locally can fall back to what the hub steps wrote.
MCP_URL="${MCP_ENDPOINT:-$(cat "$STATE/mcp-endpoint" 2>/dev/null || true)}"
MCP_TOK="${MCP_TOKEN:-$(awk 'NR==1{print $2}' "$STATE/mcp-tokens.txt" 2>/dev/null || true)}"
[[ -n "$MCP_URL" && -n "$MCP_TOK" ]] || {
  fail "MCP_ENDPOINT and MCP_TOKEN must be set in .env (they are on your workshop card)"
  exit 1; }

banner "Step 04 — seven days of logs"

say "Your agent can only see its own cluster. We are going to connect it to a"
say "platform it has never met: eight services, seven days of history, and a"
say "number of things quietly going wrong."
say ""
say "The connection is MCP -- the same protocol kagent uses for its own tools,"
say "except this server is somewhere else entirely."

# Preflight before the MCP handshake. A stale or unreachable endpoint otherwise
# surfaces as a 60-second hang and "URLError: timed out", which tells an
# attendee nothing about what to do next.
say ""
say "First, check the endpoint answers before asking an agent to depend on it."
say ""

if [[ "$MCP_URL" != https://* ]]; then
  warn "MCP_ENDPOINT is not https: $MCP_URL"
  note "The workshop endpoint is https. A plain http:// address usually means an"
  note "old .env from before the endpoint moved. Get a fresh one from the"
  note "credentials page on the slides."
fi

# Short timeout on purpose: if it is not there, say so in seconds, not minutes.
PRE=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 10 \
        -XPOST "$MCP_URL" -H 'Content-Type: application/json' -d '{}' 2>&1) || PRE="unreachable"
case "$PRE" in
  401)
    ok "endpoint is there and asking for a token — as it should"
    ;;
  200|400|406)
    note "endpoint answered ($PRE)"
    ;;
  *)
    fail "cannot reach the MCP endpoint: $MCP_URL"
    printf '\n'
    note "curl said: $PRE"
    note ""
    note "Almost always one of:"
    note "  · your .env is from an earlier session and the endpoint has moved"
    note "  · you are on a network that blocks it — try a phone hotspot"
    note "  · the hub is down; check with whoever is running the workshop"
    note ""
    note "The fix is usually a fresh .env from the credentials page on the slides."
    note "Your current value is:"
    note "  MCP_ENDPOINT=$MCP_URL"
    exit 1
    ;;
esac
say ""
# --token is read from the environment so the displayed command does not carry
# a live credential; this is on a screenshare.
printf '\n%s%s$ python3 scripts/mcp-probe.py %s --token $MCP_TOKEN%s\n\n' \
  "$BOLD" "$GREEN" "$MCP_URL" "$RESET"
MCP_TOKEN="$MCP_TOK" python3 "$REPO_ROOT/scripts/mcp-probe.py" "$MCP_URL" --token-env MCP_TOKEN

say ""
say "The token goes in a Secret; the RemoteMCPServer references it as a header."
say "Your token is yours -- it identifies you to the hub."
printf '\n%s%s$ kubectl -n kagent create secret generic workshop-logs-auth --from-literal=token=****%s\n' \
  "$BOLD" "$GREEN" "$RESET"
if kubectl -n kagent create secret generic workshop-logs-auth \
     --from-literal=token="Bearer $MCP_TOK" \
     --dry-run=client -o yaml | kubectl apply -f - >/dev/null; then
  ok "secret created"
else
  fail "could not create the MCP token secret"; exit 1
fi

cat > "$STATE/remote-mcp.yaml" <<YAML
apiVersion: kagent.dev/v1alpha2
kind: RemoteMCPServer
metadata:
  name: workshop-logs
  namespace: kagent
spec:
  description: Seven days of logs from the workshop platform, via Grafana and Loki.
  protocol: STREAMABLE_HTTP
  url: ${MCP_URL}
  timeout: 60s
  sseReadTimeout: 5m
  headersFrom:
    - name: Authorization
      valueFrom:
        type: Secret
        name: workshop-logs-auth
        key: token
YAML

run "cat '$STATE/remote-mcp.yaml'"
run "kubectl apply -f '$STATE/remote-mcp.yaml'"

wait_for "kagent to connect and discover the tools" 300 \
  "[[ \"\$(kubectl -n kagent get remotemcpserver workshop-logs -o jsonpath='{.status.conditions[?(@.type==\"Accepted\")].status}' 2>/dev/null)\" == 'True' ]]"

say ""
say "kagent has connected and discovered what the server offers:"
run "kubectl -n kagent get remotemcpserver workshop-logs -o jsonpath='{.status.discoveredTools[*].name}' | tr ' ' '\n'"

say ""
say "Now a second agent. cluster-scout is untouched -- agents are cheap, and two"
say "narrow ones beat one that tries to do everything."
say ""
say "Here is what makes this one different: it has two tool servers instead of"
say "one. Its own cluster, and the hub."
run "sed -n '/^    tools:/,/^    a2aConfig:/p' '$HERE/agent.yaml' | sed '\$d'"

say ""
say "It is a new resource, not an edit. What you have now:"
run "kubectl get agents -n kagent"

say ""
say "And after applying it:"
run "kubectl apply -f '$HERE/agent.yaml'"
run "kubectl get agents -n kagent"
say ""
say "cluster-scout is still there, untouched. Re-run this step and nothing"
say "changes — it is the same resource either way."
# rollout status covers the Deployment; the endpoints check below covers
# whether it is actually serving. The Agent resource's Ready condition in
# between told us nothing the other two did not.
run "kubectl -n kagent rollout status deploy/log-detective --timeout=180s"

run "bash '$REPO_ROOT/scripts/ui.sh' start"
UI="http://127.0.0.1:${UI_PORT:-8082}/api/a2a/kagent"
# The card comes from the controller, so it is not evidence the agent pod is
# serving. Wait for the Service to actually have a ready endpoint.
wait_for "log-detective to start serving" 180 \
  "[[ -n \"\$(kubectl -n kagent get endpoints log-detective -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null)\" ]]"

say ""
say "Start with something simple, to prove it can see the data at all."
run "python3 '$REPO_ROOT/scripts/ask-agent.py' '$UI/log-detective' \
  'Which services are sending logs to the workshop-loki datasource? Just list them.'"

printf '\n'
ok "log-detective can read seven days of production logs."
say ""
say "Everything from here is a question. Try these, one at a time:"
printf '\n'
note "'Has anything got worse in the last week?'"
note "'Are there any problems that happen on a schedule?'"
note "'Which service is least healthy right now?'"
note "'Where is our log volume going?'"
note "'Is anything about to break that has not broken yet?'"
printf '\n'
say "Ask them with:"
note "In the dashboard at http://localhost:${UI_PORT:-8082} — pick log-detective"
note "or from here:  python3 scripts/ask-agent.py \\"
note "                  http://127.0.0.1:${UI_PORT:-8082}/api/a2a/kagent/log-detective 'your question'"
note "next:  make step-05   (a report every morning)"
