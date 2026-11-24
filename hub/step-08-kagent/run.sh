#!/usr/bin/env bash
# title: Install kagent on the hub, behind a guard
#
# Round two of the CTF is the real kagent dashboard, shared by the whole room.
# Out of the box that would mean one user, everyone reading everyone's chats,
# and a Delete button on the agent. This step installs kagent so that none of
# those are true:
#
#   kagent        no built-in agents, no Kubernetes tools -- only the logs
#   kagent-guard  sits between the dashboard and the controller; players can
#                 chat, and only chat
#   workshop-logs the read-only Loki MCP endpoint from hub-06
#
# No agents are created here. You add those with `make agent-01` and friends
# while you present, and they appear on every player's page as they come up.
source "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib.sh"

STATE="$REPO_ROOT/.state"
export KUBECONFIG="$STATE/hub.kubeconfig"
[[ -f "$KUBECONFIG" ]] || { fail "no hub kubeconfig — run 'make hub-01' first"; exit 1; }
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NS="${OBS_NAMESPACE:-observability}"
KAGENT_VERSION="${KAGENT_VERSION:-0.10.1}"
MODEL="${RELAX_MODEL:-DeepSeek-V4-Pro}"
BASE_URL="${RELAX_BASE_URL:-https://api.relax.ai/v1}"

banner "Hub — step 08: kagent, shared safely"

# ------------------------------------------------------------- the model key
# One key serves the whole room now, so its rate limit is the room's rate
# limit. Ask the relax.ai team what that is before the day.
KEY="${RELAX_API_KEY-}"
if [[ -z "$KEY" && -s "$STATE/relax-keys.txt" ]]; then
  KEY="$(grep -ve '^\s*$' -e '^\s*#' "$STATE/relax-keys.txt" | head -1 | tr -d '[:space:]')"
fi
[[ -n "$KEY" ]] || { fail "no model key — set RELAX_API_KEY in .env"; exit 1; }
[[ -s "$STATE/mcp-tokens.txt" ]] || { fail "no MCP tokens — run 'make hub-06' first"; exit 1; }
MCP_TOKEN="$(awk 'NR==1{print $2}' "$STATE/mcp-tokens.txt")"

run "helm upgrade --install kagent-crds oci://ghcr.io/kagent-dev/kagent/helm/kagent-crds \
  --namespace kagent --create-namespace --wait --timeout 5m \
  --version '$KAGENT_VERSION'"

# Not shown via run: it carries a live key and this terminal may be shared.
printf '\n%s%s$ kubectl -n kagent create secret generic kagent-relax --from-literal=RELAX_API_KEY=****%s\n' \
  "$BOLD" "$GREEN" "$RESET"
kubectl -n kagent create secret generic kagent-relax \
  --from-literal=RELAX_API_KEY="$KEY" \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null \
  || { fail "could not create the model key secret"; exit 1; }
kubectl -n kagent create secret generic workshop-logs-auth \
  --from-literal=token="Bearer $MCP_TOKEN" \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null \
  || { fail "could not create the MCP token secret"; exit 1; }
ok "secrets created"

# ----------------------------------------------------------------- the guard
# Before kagent, because the dashboard is configured to call it from its
# first request.
#
# The guard is hidden from the slide recordings (hide_begin .. hide_end): it
# is still installed and still tested, it is just not part of that story.
hide_begin
say ""
say "The guard first. It is thirty lines of nginx, and it is the reason a room"
say "full of people can share one kagent: reads pass, conversations pass,"
say "everything else is refused."
run "sed -n '/^server {/,\$p' '$HERE/guard.conf'"

run_quiet "kubectl -n kagent create configmap kagent-guard \
  --from-file=guard.conf='$HERE/guard.conf' \
  --from-file=proxy.inc='$HERE/proxy.inc' \
  --dry-run=client -o yaml | kubectl apply -f -"

cat > "$STATE/kagent-guard.yaml" <<YAML
apiVersion: apps/v1
kind: Deployment
metadata: { name: kagent-guard, namespace: kagent }
spec:
  replicas: 2
  selector: { matchLabels: { app: kagent-guard } }
  template:
    metadata:
      labels: { app: kagent-guard }
      annotations:
        guard/checksum: "$(cat "$HERE/guard.conf" "$HERE/proxy.inc" | sha256sum | cut -c1-16)"
    spec:
      containers:
        - name: nginx
          image: ${GUARD_IMAGE:-nginx:1.27-alpine}
          ports: [{ containerPort: 8080 }]
          volumeMounts:
            - { name: conf, mountPath: /etc/nginx/conf.d/default.conf, subPath: guard.conf }
            - { name: conf, mountPath: /etc/nginx/guard/proxy.inc,     subPath: proxy.inc }
          readinessProbe:
            httpGet: { path: /healthz, port: 8080 }
          resources:
            requests: { cpu: 20m, memory: 32Mi }
            limits:   { memory: 128Mi }
      volumes:
        - name: conf
          configMap: { name: kagent-guard }
---
apiVersion: v1
kind: Service
metadata: { name: kagent-guard, namespace: kagent }
spec:
  selector: { app: kagent-guard }
  ports: [{ name: http, port: 8080, targetPort: 8080 }]
YAML
run "kubectl apply -f '$STATE/kagent-guard.yaml'"
hide_end

# ------------------------------------------------------------------- kagent
OVERRIDE=""
[[ "$MODEL"    != "DeepSeek-V4-Pro" ]]            && OVERRIDE+="   --set providers.openAI.model=$MODEL"
[[ "$BASE_URL" != "https://api.relax.ai/v1" ]]    && OVERRIDE+="   --set providers.openAI.config.baseUrl=$BASE_URL"
KAGENT_URL="$(cat "$STATE/kagent-endpoint" 2>/dev/null || true)"
[[ -n "$KAGENT_URL" ]] && OVERRIDE+="   --set ui.externalUrl=$KAGENT_URL"

say ""
say "kagent itself. No built-in agents and no Kubernetes tools: the values"
say "file turns them all off, and points the model at relax.ai."
run "helm upgrade --install kagent oci://ghcr.io/kagent-dev/kagent/helm/kagent \
  --namespace kagent --wait --timeout 10m \
  --values '$HERE/values.yaml'$OVERRIDE \
  --version '$KAGENT_VERSION'"

wait_for "the kagent controller to be ready" 600 \
  "kubectl -n kagent get deploy kagent-controller -o jsonpath='{.status.readyReplicas}' 2>/dev/null | grep -q '^[1-9]'"
# The guard resolves the controller's name when nginx starts, so it can only
# become ready once the controller Service exists.
hide_begin
run "kubectl -n kagent rollout restart deploy/kagent-guard"
run "kubectl -n kagent rollout status deploy/kagent-guard --timeout=300s"
hide_end
say ""
say "What that started: the controller, the dashboard, and a database for"
say "the conversations. No agents yet."
run "kubectl -n kagent get pods"

ACTUAL=$(kubectl -n kagent get modelconfig default-model-config -o jsonpath='{.spec.openAI.baseUrl}' 2>/dev/null || true)
if [[ "$ACTUAL" != "$BASE_URL" ]]; then
  fail "ModelConfig baseUrl is '${ACTUAL:-empty}', expected '$BASE_URL'"
  exit 1
fi

LEFT=$(kubectl -n kagent get agents.kagent.dev --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [[ "$LEFT" != "0" && -z "${DEMO_RECORD-}" ]]; then
  note "$LEFT agent(s) already exist in the kagent namespace:"
  kubectl -n kagent get agents.kagent.dev --no-headers | awk '{print "    " $1}'
  note "players will see every one of them in round two"
fi

# --------------------------------------------------------------- the logs
say ""
say "The only tool any agent on this cluster can be given: the read-only Loki"
say "endpoint from hub-06, reached inside the cluster."
cat > "$STATE/hub-remote-mcp.yaml" <<YAML
apiVersion: kagent.dev/v1alpha2
kind: RemoteMCPServer
metadata:
  name: workshop-logs
  namespace: kagent
spec:
  description: Seven days of logs from the workshop platform, via Grafana and Loki.
  protocol: STREAMABLE_HTTP
  url: http://mcp-public.${NS}.svc.cluster.local/mcp
  timeout: 60s
  sseReadTimeout: 5m
  headersFrom:
    - name: Authorization
      valueFrom:
        type: Secret
        name: workshop-logs-auth
        key: token
YAML
run "kubectl apply -f '$STATE/hub-remote-mcp.yaml'"
wait_for "kagent to connect and discover the log tools" 300 \
  "[[ \"\$(kubectl -n kagent get remotemcpserver workshop-logs -o jsonpath='{.status.conditions[?(@.type==\"Accepted\")].status}' 2>/dev/null)\" == 'True' ]]"
run "kubectl -n kagent get remotemcpserver workshop-logs \
  -o jsonpath='{.status.discoveredTools[*].name}' | tr ' ' '\n'"

# ------------------------------------------------------------- verification
hide_begin
say ""
say "Now prove the guard does what it says, from the dashboard's side of it."
trap cleanup_port_forwards EXIT
port_forward kagent svc/kagent-guard 18083:8080
G="http://127.0.0.1:18083"
BAD=0
check() {
  if [[ "$2" == "$3" ]]; then printf '  %s%s✓%s %s\n' "$BOLD" "$GREEN" "$RESET" "$1"
  else printf '  %s%s✗%s %s (expected %s, got %s)\n' "$BOLD" "$RED" "$RESET" "$1" "$2" "$3"; BAD=1; fi
}
code() { curl -sS -o /dev/null -w '%{http_code}' --max-time 20 "$@" || echo 000; }
J='Content-Type: application/json'

check "agents can be listed"                 200 "$(code "$G/api/agents")"
check "an agent cannot be created"           403 "$(code -XPOST "$G/api/agents" -H "$J" -d '{}')"
check "an agent cannot be edited"            403 "$(code -XPUT "$G/api/agents" -H "$J" -d '{}')"
check "an agent cannot be deleted"           403 "$(code -XDELETE "$G/api/agents/kagent/log-detective")"
check "the model cannot be changed"          403 "$(code -XPUT "$G/api/modelconfigs/kagent/default-model-config" -H "$J" -d '{}')"
check "a tool server cannot be added"        403 "$(code -XPOST "$G/api/toolservers" -H "$J" -d '{}')"
check "tools cannot be called directly"      403 "$(code -XPOST "$G/api/mcpapps/kagent/workshop-logs/tools/query_loki_logs/call" -H "$J" -d '{}')"
check "nobody can pose as another player"    403 "$(code "$G/api/sessions?user_id=someone-else")"

# Privacy: a chat session made by one player must be invisible to another.
SID="guard-probe-$(date +%s)"
MADE=$(code -XPOST "$G/api/sessions" -H "$J" -H 'X-User-Id: probe-a@ctf' \
  -d "{\"id\":\"$SID\",\"name\":\"guard probe\",\"agent_ref\":\"kagent/guard-probe\"}")
if [[ "$MADE" =~ ^2 ]]; then
  check "a player can read their own chat"     200 "$(code "$G/api/sessions/$SID" -H 'X-User-Id: probe-a@ctf')"
  OTHER=$(code "$G/api/sessions/$SID" -H 'X-User-Id: probe-b@ctf')
  if [[ "$OTHER" == "200" ]]; then check "another player cannot read it" "not 200" "$OTHER"
  else check "another player cannot read it" "$OTHER" "$OTHER"; fi
  code -XDELETE "$G/api/sessions/$SID" -H 'X-User-Id: probe-a@ctf' >/dev/null
else
  # Creating a session needs an agent to attach it to on some versions. Not a
  # guard failure -- but say so, because it means privacy is unproven here.
  warn "could not create a probe session (HTTP $MADE) — chat privacy NOT verified"
  note "after 'make agent-01', open the dashboard in two browsers as two players"
  note "and confirm neither can see the other's chat"
fi

hide_end
if (( BAD )); then
  fail "the guard is not enforcing what it should — do not open this to a room"
  note "kubectl -n kagent logs deploy/kagent-guard --tail=40"
  exit 1
fi

printf '\n'
if [[ -n "${DEMO_RECORD-}" ]]; then ok "kagent is installed, and it can read the logs."; exit 0; fi
ok "kagent is installed, and players can do nothing to it but talk."
note "agents:  make agent-01 …   (see agents/ — add them while you present)"
note "next:    make hub-09   (public HTTPS addresses for all of it)"
