#!/usr/bin/env bash
# title: Give your agent seven days of production logs
source "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib.sh"

STATE="$REPO_ROOT/.state"
export KUBECONFIG="$STATE/workshop.kubeconfig"
[[ -f "$KUBECONFIG" ]] || { fail "no kubeconfig — run 'make step-02' first"; exit 1; }
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Attendees get these on their workshop card, in .env. The instructor running
# the whole thing locally can fall back to what hub step 06 wrote.
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

say ""
say "First, check the endpoint answers before asking an agent to depend on it."
run "python3 '$REPO_ROOT/scripts/mcp-probe.py' '$MCP_URL' --token '$MCP_TOK'"

say ""
say "The token goes in a Secret; the RemoteMCPServer references it as a header."
say "Your token is yours -- it identifies you to the hub."
run_quiet "kubectl -n kagent create secret generic workshop-logs-auth \
  --from-literal=token='Bearer $MCP_TOK' \
  --dry-run=client -o yaml | kubectl apply -f -"

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
say "Now give the agent those tools. This is the same agent as step 03 with one"
say "extra block under tools -- and a system prompt that tells it how to use them."
run "diff -u '$REPO_ROOT/workshop/step-03-agent/agent.yaml' '$HERE/agent.yaml' | head -60 || true"

run "kubectl apply -f '$HERE/agent.yaml'"
run "kubectl -n kagent rollout status deploy/my-agent --timeout=180s"
wait_for "my-agent to be ready" 300 \
  "[[ \"\$(kubectl -n kagent get agent my-agent -o jsonpath='{.status.conditions[?(@.type==\"Ready\")].status}' 2>/dev/null)\" == 'True' ]]"

trap cleanup_port_forwards EXIT
port_forward kagent svc/my-agent 8081:8080
wait_for "your agent to answer" 120 "curl -sf -o /dev/null http://127.0.0.1:8081/.well-known/agent-card.json"

say ""
say "Start with something simple, to prove it can see the data at all."
run "python3 '$REPO_ROOT/scripts/ask-agent.py' http://127.0.0.1:8081 \
  'Which services are sending logs to the workshop-loki datasource? Just list them.'"

printf '\n'
ok "Your agent can now read seven days of production logs."
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
note "python3 scripts/ask-agent.py http://127.0.0.1:8081 'your question'"
note "(or use the UI: kubectl -n kagent port-forward svc/kagent-ui 8080:8080)"
note "next:  make step-05   (a report every morning)"
