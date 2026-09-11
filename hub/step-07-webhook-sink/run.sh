#!/usr/bin/env bash
# title: Deploy the webhook sink and wall
#
# Attendees' report CronJobs POST here and watch their own page; /wall goes on
# the projector. No database, no volume: a code is an opaque routing key the
# server never registers, so a restart invalidates nothing.
source "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib.sh"

STATE="$REPO_ROOT/.state"
export KUBECONFIG="$STATE/hub.kubeconfig"
[[ -f "$KUBECONFIG" ]] || { fail "no hub kubeconfig — run 'make hub-01' first"; exit 1; }
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NS="${OBS_NAMESPACE:-observability}"
IMAGE="${GENERATOR_IMAGE:-python:3.12-alpine}"

banner "Hub — step 07: the wall"

say "Attendees open this, get a word-pair code, and put the URL in their .env."
say "Their report lands on their page. Yours is /wall -- put it on the"
say "projector during step 05 and watch the room's reports arrive."

run_quiet "kubectl -n '$NS' create configmap webhook-sink \
  --from-file=sink.py='$HERE/sink.py' \
  --dry-run=client -o yaml | kubectl apply -f -"

cat > "$STATE/sink.yaml" <<YAML
apiVersion: apps/v1
kind: Deployment
metadata: { name: webhook-sink, namespace: ${NS} }
spec:
  replicas: 1        # in-memory state; there is no reason to scale this
  selector: { matchLabels: { app: webhook-sink } }
  template:
    metadata:
      labels: { app: webhook-sink }
      annotations:
        sink/checksum: "$(sha256sum "$HERE/sink.py" | cut -c1-16)"
    spec:
      containers:
        - name: sink
          image: ${IMAGE}
          command: ["python3", "/app/sink.py"]
          env:
            - { name: PORT, value: "8080" }
            - { name: PYTHONUNBUFFERED, value: "1" }
          ports: [{ containerPort: 8080 }]
          volumeMounts: [{ name: app, mountPath: /app }]
          readinessProbe:
            httpGet: { path: /healthz, port: 8080 }
          resources:
            requests: { cpu: 20m, memory: 48Mi }
            limits:   { memory: 192Mi }
      volumes:
        - name: app
          configMap: { name: webhook-sink }
---
apiVersion: v1
kind: Service
metadata: { name: webhook-sink, namespace: ${NS} }
spec:
  type: LoadBalancer
  selector: { app: webhook-sink }
  ports: [{ name: http, port: 80, targetPort: 8080 }]
YAML

run "kubectl apply -f '$STATE/sink.yaml'"
run "kubectl -n '$NS' rollout status deploy/webhook-sink --timeout=300s"

wait_for "LoadBalancer to get an address" 600 \
  "[[ -n \"\$(kubectl -n '$NS' get svc webhook-sink -o jsonpath='{.status.loadBalancer.ingress[0].ip}')\" ]]"
SINK_IP=$(kubectl -n "$NS" get svc webhook-sink -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
SINK_URL="http://${SINK_IP}"
echo "$SINK_URL" > "$STATE/sink-endpoint"

wait_for "the sink to answer" 300 "curl -sf -o /dev/null '$SINK_URL/healthz'"

# State is in memory, so during a rolling update deliveries land in whichever
# pod is serving. Wait for exactly one steady pod before verifying, or the
# POST and the read-back can hit different replicas.
wait_for "exactly one sink pod" 180 \
  "[[ \$(kubectl -n '$NS' get pod -l app=webhook-sink --no-headers 2>/dev/null | wc -l) -eq 1 ]]"

# ------------------------------------------------------------- verification
say ""
say "Checking the guard rails, not just that it is up. This is a public write"
say "endpoint you are about to announce to a room."

CODE="smoke-$(date +%s | tail -c 5)"
say ""
say "1. A delivery is accepted and readable."
run "curl -sS -XPOST '$SINK_URL/hook/$CODE' -H 'Content-Type: application/json' -d '{\"text\":\"smoke test report\"}'"
HITS=0
for _ in $(seq 1 10); do
  HITS=$(curl -sS "$SINK_URL/api/c/$CODE" | python3 -c 'import json,sys;print(len(json.load(sys.stdin)["items"]))' 2>/dev/null || echo 0)
  [[ "${HITS:-0}" -ge 1 ]] && break
  sleep 2
done
[[ "${HITS:-0}" -ge 1 ]] && ok "read back $HITS delivery" || { fail "delivery not readable"; exit 1; }

say ""
say "2. An oversized body is refused."
CODE2=$(head -c 300000 /dev/zero | tr '\0' 'a' | curl -sS -o /dev/null -w '%{http_code}' -XPOST "$SINK_URL/hook/$CODE" --data-binary @-)
[[ "$CODE2" == "413" ]] && ok "413 for a body over 256KB" || { fail "expected 413, got $CODE2"; exit 1; }

say ""
say "3. A hostile payload is stored but never rendered as markup."
run_quiet "curl -sS -XPOST '$SINK_URL/hook/$CODE' -d '<img src=x onerror=alert(1)>'"
if curl -sS "$SINK_URL/wall" | grep -q "onerror"; then
  fail "the wall rendered an injected payload — do not put this on a projector"
  exit 1
fi
ok "the wall page contains no injected markup (bodies render via textContent)"

printf '\n'
ok "The wall is live."
note "attendees:  $SINK_URL"
note "projector:  $SINK_URL/wall"
warn "Plain HTTP, like the MCP endpoint. Same trade-off, same fix needed."
note "next:  make step-05   (the report CronJob)"
