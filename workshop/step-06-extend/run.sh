#!/usr/bin/env bash
# title: Cut the cord, and make it yours
#
# Doubles as the WiFi fallback for step 04: if the hub is unreachable, this
# deploys the same stack into the attendee's own cluster with the same seeded
# data, and step 04's questions work unchanged.
source "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib.sh"

STATE="$REPO_ROOT/.state"
export KUBECONFIG="$STATE/workshop.kubeconfig"
[[ -f "$KUBECONFIG" ]] || { fail "no kubeconfig — run 'make step-02' first"; exit 1; }
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NS="${LOCAL_OBS_NAMESPACE:-observability}"
IMAGE="${GENERATOR_IMAGE:-python:3.12-alpine}"
DAYS="${LOCAL_BACKFILL_DAYS:-7}"

banner "Step 06 — make it yours"

say "Right now your agent depends on two things you do not own: the workshop"
say "hub, and a shared endpoint that goes away. This step removes both, so what"
say "you walk out with keeps working."
say ""
say "It deploys the same observability stack into your own cluster: Loki, the"
say "applications generating logs, and an MCP server. Then it repoints your"
say "agent at your copy."

run "kubectl create namespace '$NS' --dry-run=client -o yaml | kubectl apply -f -"
run "helm repo add grafana https://grafana.github.io/helm-charts --force-update >/dev/null && helm repo update grafana >/dev/null && echo ok"

say ""
say "Loki, sized to sit alongside kagent on two small nodes."
run "helm upgrade --install loki grafana/loki --namespace '$NS' \
  --version '${LOKI_CHART_VERSION:-6.24.0}' \
  --values '$HERE/loki-values.yaml' --wait --timeout 10m"
wait_for "Loki to be ready" 600 \
  "kubectl -n '$NS' get pod -l app.kubernetes.io/component=single-binary -o jsonpath='{.items[*].status.containerStatuses[*].ready}' | grep -q true"

say ""
say "Grafana, with Loki wired in as a datasource."
PWFILE="$STATE/local-grafana-password"
[[ -s "$PWFILE" ]] || { head -c 18 /dev/urandom | base64 | tr -d '/+=' | head -c 20 > "$PWFILE"; chmod 600 "$PWFILE"; }
GPW="$(cat "$PWFILE")"
cat > "$STATE/local-grafana-values.yaml" <<YAML
adminUser: admin
adminPassword: "${GPW}"
persistence: { enabled: false }
resources:
  requests: { cpu: 50m, memory: 128Mi }
  limits:   { memory: 384Mi }
datasources:
  datasources.yaml:
    apiVersion: 1
    datasources:
      - name: Loki
        type: loki
        uid: workshop-loki
        access: proxy
        url: http://loki.${NS}.svc.cluster.local:3100
        isDefault: true
        jsonData: { maxLines: 5000 }
grafana.ini:
  analytics: { reporting_enabled: false, check_for_updates: false }
YAML
run "helm upgrade --install grafana grafana/grafana --namespace '$NS' \
  --version '${GRAFANA_CHART_VERSION:-8.8.2}' \
  --values '$STATE/local-grafana-values.yaml' --wait --timeout 8m"

say ""
say "The applications, and seven days of history behind them."
run_quiet "kubectl -n '$NS' create configmap log-generator \
  --from-file=generator.py='$REPO_ROOT/hub/step-04-workloads/generator.py' \
  --dry-run=client -o yaml | kubectl apply -f -"

cat > "$STATE/local-stack.yaml" <<YAML
apiVersion: apps/v1
kind: Deployment
metadata: { name: log-generator, namespace: ${NS} }
spec:
  # Starts stopped ON PURPOSE. A generator writing "now" into these streams
  # before the backfill runs makes every backdated entry too far behind for
  # Loki to accept. Backfill first, then scale this to 1.
  replicas: 0
  selector: { matchLabels: { app: log-generator } }
  template:
    metadata: { labels: { app: log-generator } }
    spec:
      containers:
        - name: generator
          image: ${IMAGE}
          command: ["python3", "/app/generator.py", "--live"]
          env:
            - { name: LOKI_URL, value: "http://loki.${NS}.svc.cluster.local:3100" }
            - { name: PYTHONUNBUFFERED, value: "1" }
          volumeMounts: [{ name: app, mountPath: /app }]
          resources:
            requests: { cpu: 50m, memory: 64Mi }
            limits:   { memory: 192Mi }
      volumes:
        - name: app
          configMap: { name: log-generator }
---
apiVersion: apps/v1
kind: Deployment
metadata: { name: mcp-grafana, namespace: ${NS} }
spec:
  replicas: 1
  selector: { matchLabels: { app: mcp-grafana } }
  template:
    metadata: { labels: { app: mcp-grafana } }
    spec:
      containers:
        - name: mcp
          image: ${MCP_IMAGE:-mcp/grafana:latest}
          args:
            - "-t"
            - "streamable-http"
            - "--address"
            - "0.0.0.0:8000"
            - "--disable-write"
            - "-allowed-hosts"
            - "*"
          env:
            - { name: GRAFANA_URL, value: "http://grafana.${NS}.svc.cluster.local" }
            - { name: GRAFANA_USERNAME, value: "admin" }
            - { name: GRAFANA_PASSWORD, value: "${GPW}" }
          ports: [{ containerPort: 8000 }]
          resources:
            requests: { cpu: 50m, memory: 64Mi }
            limits:   { memory: 256Mi }
---
apiVersion: v1
kind: Service
metadata: { name: mcp-grafana, namespace: ${NS} }
spec:
  selector: { app: mcp-grafana }
  ports: [{ port: 8000, targetPort: 8000 }]
YAML
run "kubectl apply -f '$STATE/local-stack.yaml'"
run "kubectl -n '$NS' rollout status deploy/mcp-grafana --timeout=300s"

say ""
say "Backfilling seven days of history. The generator is deliberately not"
say "running yet: Loki only accepts out-of-order writes within a narrow window,"
say "so anything stamping 'now' first would make the backfill too far behind."
# Seed from empty every time. Backfilling on top of existing data hits Loki's
# out-of-order window and silently leaves holes, and this stack is disposable,
# so a clean start is both safer and repeatable.
if kubectl -n "$NS" get pvc storage-loki-0 >/dev/null 2>&1 && \
   [[ -n "$(kubectl -n "$NS" get job local-backfill -o jsonpath='{.status.succeeded}' 2>/dev/null)" ]]; then
  note "already seeded — re-seeding from empty so the result is predictable"
fi
run "kubectl -n '$NS' scale statefulset loki --replicas=0"
wait_for "Loki to stop" 180 "! kubectl -n '$NS' get pod loki-0 >/dev/null 2>&1"
run "kubectl -n '$NS' delete pvc storage-loki-0 --ignore-not-found"
run "kubectl -n '$NS' scale statefulset loki --replicas=1"
wait_for "Loki to come back empty" 420 \
  "[[ \"\$(kubectl -n '$NS' get pod loki-0 -o jsonpath='{.status.containerStatuses[*].ready}' 2>/dev/null)\" == 'true true' ]]"

run "kubectl -n '$NS' delete job local-backfill --ignore-not-found"
cat > "$STATE/local-backfill.yaml" <<YAML
apiVersion: batch/v1
kind: Job
metadata: { name: local-backfill, namespace: ${NS} }
spec:
  backoffLimit: 1
  ttlSecondsAfterFinished: 1800
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: backfill
          image: ${IMAGE}
          command: ["python3", "/app/generator.py", "--backfill", "--days", "${DAYS}"]
          env:
            - { name: LOKI_URL, value: "http://loki.${NS}.svc.cluster.local:3100" }
            - { name: PYTHONUNBUFFERED, value: "1" }
          volumeMounts: [{ name: app, mountPath: /app }]
          resources:
            requests: { cpu: 200m, memory: 128Mi }
            limits:   { memory: 512Mi }
      volumes:
        - name: app
          configMap: { name: log-generator }
YAML
run "kubectl apply -f '$STATE/local-backfill.yaml'"
wait_for "backfill to finish" 1800 \
  "[[ -n \"\$(kubectl -n '$NS' get job local-backfill -o jsonpath='{.status.succeeded}{.status.failed}' 2>/dev/null)\" ]]"
if [[ "$(kubectl -n "$NS" get job local-backfill -o jsonpath='{.status.succeeded}')" != "1" ]]; then
  fail "the backfill failed — your dataset would have holes in it"
  run_quiet "kubectl -n '$NS' logs job/local-backfill --tail=20"
  exit 1
fi
run "kubectl -n '$NS' logs job/local-backfill --tail=3"

say ""
say "History is in. Now start live generation on top of it."
run "kubectl -n '$NS' scale deploy/log-generator --replicas=1"

# ------------------------------------------------------------ repoint kagent
say ""
say "Now repoint your agent. This is the only change it needs: same agent, same"
say "tools, a URL inside your own cluster instead of one on the internet."
cat > "$STATE/local-mcp.yaml" <<YAML
apiVersion: kagent.dev/v1alpha2
kind: RemoteMCPServer
metadata:
  name: workshop-logs
  namespace: kagent
spec:
  description: Your own copy of the workshop log platform.
  protocol: STREAMABLE_HTTP
  url: http://mcp-grafana.${NS}.svc.cluster.local:8000/mcp
  timeout: 60s
  sseReadTimeout: 5m
YAML
run "kubectl apply -f '$STATE/local-mcp.yaml'"
wait_for "kagent to rediscover the tools locally" 300 \
  "[[ \"\$(kubectl -n kagent get remotemcpserver workshop-logs -o jsonpath='{.status.conditions[?(@.type==\"Accepted\")].status}' 2>/dev/null)\" == 'True' ]]"
run "kubectl -n kagent get remotemcpserver workshop-logs -o jsonpath='{.status.discoveredTools[*].name}' | tr ' ' '\n'"

run "kubectl -n kagent rollout restart deploy/my-agent"
run "kubectl -n kagent rollout status deploy/my-agent --timeout=300s"

kubectl -n kagent port-forward svc/my-agent 8081:8080 >/dev/null 2>&1 &
PF=$!
trap 'kill $PF 2>/dev/null || true' EXIT
wait_for "a route to your agent" 60 "curl -sf -o /dev/null http://127.0.0.1:8081/.well-known/agent-card.json"

say ""
say "Same question as step 04. Nothing outside your cluster is involved now."
run "python3 '$REPO_ROOT/scripts/ask-agent.py' http://127.0.0.1:8081 \
  'Which services are sending logs, and how many errors were there in the last 24 hours?'"

printf '\n'
ok "Your cluster no longer depends on the workshop hub."
say ""
say "One thing left, and it is not automated on purpose: the relax.ai key."
note "The key on your card is yours, but if you want to swap it:"
note "  kubectl -n kagent create secret generic kagent-relax \\"
note "    --from-literal=RELAX_API_KEY=<your-key> --dry-run=client -o yaml | kubectl apply -f -"
note "  kubectl -n kagent rollout restart deploy/my-agent"
printf '\n'
say "Where to take it next:"
note "$HERE/my-agent.yaml — a commented scaffold for your own agent"
note "docs/AFTER.md — what this costs, and five things worth trying"
