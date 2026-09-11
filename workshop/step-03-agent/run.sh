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
kubectl -n kagent port-forward svc/k8s-agent 8080:8080 >/dev/null 2>&1 &
PF1=$!
trap 'kill $PF1 $PF2 2>/dev/null || true' EXIT
wait_for "a route to the agent" 60 "curl -sf -o /dev/null http://127.0.0.1:8080/.well-known/agent-card.json"

run "python3 '$REPO_ROOT/scripts/ask-agent.py' http://127.0.0.1:8080 \
  'How many pods are running in the kagent namespace, and are any of them unhealthy?'"

say ""
say "That answer came from your cluster, via a model running on relax.ai."
say "Nothing was hard-coded. Now write your own agent."

pause "look at the agent definition"
run "cat '$HERE/agent.yaml'"

say ""
say "Three things: which model, what it is for, and which tools it may use."
run "kubectl apply -f '$HERE/agent.yaml'"

wait_for "my-agent to be ready" 300 \
  "[[ \"\$(kubectl -n kagent get agent my-agent -o jsonpath='{.status.conditions[?(@.type==\"Ready\")].status}' 2>/dev/null)\" == 'True' ]]"
run "kubectl -n kagent get agents"

kubectl -n kagent port-forward svc/my-agent 8081:8080 >/dev/null 2>&1 &
PF2=$!
wait_for "a route to your agent" 60 "curl -sf -o /dev/null http://127.0.0.1:8081/.well-known/agent-card.json"

run "python3 '$REPO_ROOT/scripts/ask-agent.py' http://127.0.0.1:8081 \
  'What namespaces exist in this cluster, and what is running in each?'"

printf '\n'
ok "You have an agent of your own."
say ""
say "It can only see this cluster. In step 04 you give it seven days of logs"
say "from a fleet of applications it has never met."
note "edit $HERE/agent.yaml and re-run 'make step-03' to change its behaviour"
note "the kagent UI:  kubectl -n kagent port-forward svc/kagent-ui 8080:8080"
note "next:  make step-04"
