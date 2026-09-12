#!/usr/bin/env bash
# title: Build and talk to your first agent
source "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib.sh"

STATE="$REPO_ROOT/.state"
export KUBECONFIG="$STATE/workshop.kubeconfig"
[[ -f "$KUBECONFIG" ]] || { fail "no kubeconfig — run 'make step-02' first"; exit 1; }
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

banner "Step 03 — your first agent"

say "kagent ships a Kubernetes agent out of the box. Before writing your own,"
say "check the whole path works: your question goes to the agent, the agent"
say "thinks using relax.ai, calls Kubernetes tools, and answers."

wait_for "the built-in k8s-agent to be ready" 300 \
  "[[ \"\$(kubectl -n kagent get agent k8s-agent -o jsonpath='{.status.conditions[?(@.type==\"Ready\")].status}' 2>/dev/null)\" == 'True' ]]"

# Port-forward for the rest of the step.
# The dashboard is the one port-forward for the whole session. It proxies A2A
# for every agent at /api/a2a/<namespace>/<name>, so nothing here needs a
# forward of its own.
run "bash '$REPO_ROOT/scripts/ui.sh' start"
UI="http://127.0.0.1:${UI_PORT:-8082}/api/a2a/kagent"
wait_for "the dashboard to answer for k8s-agent" 120 \
  "curl -sf -o /dev/null '$UI/k8s-agent/.well-known/agent-card.json'"

run "python3 '$REPO_ROOT/scripts/ask-agent.py' '$UI/k8s-agent' \
  'How many pods are running in the kagent namespace, and are any of them unhealthy?'"

say ""
say "That answer came from your cluster, via a model running on relax.ai."
say "Nothing was hard-coded. Now write your own agent."

run "cat '$HERE/agent.yaml'"

say ""
say "Three things: which model, what it is for, and which tools it may use."
run "kubectl apply -f '$HERE/agent.yaml'"

wait_for "cluster-scout to be ready" 300 \
  "[[ \"\$(kubectl -n kagent get agent cluster-scout -o jsonpath='{.status.conditions[?(@.type==\"Ready\")].status}' 2>/dev/null)\" == 'True' ]]"
run "kubectl -n kagent get agents"

wait_for "cluster-scout to appear in the dashboard" 120 \
  "curl -sf -o /dev/null '$UI/cluster-scout/.well-known/agent-card.json'"

run "python3 '$REPO_ROOT/scripts/ask-agent.py' '$UI/cluster-scout' \
  'What namespaces exist in this cluster, and what is running in each?'"

say ""
say "Everything above went through the dashboard, which is also how you use it."
say "Open it, pick cluster-scout, and ask it something yourself. It stays up for"
say "the rest of the session, and every agent you build shows up in it."

printf '\n'
ok "You have an agent of your own."
say ""
say "cluster-scout can only see this cluster. In step 04 you build a second"
say "agent that can also see seven days of logs from a platform it has never"
say "met — and you will have both, side by side, in the dashboard."
note "edit $HERE/agent.yaml and re-run 'make step-03' to change how it behaves"
note "dashboard: http://localhost:${UI_PORT:-8082}   (make ui / make ui-stop)"
note "next:  make step-04"
