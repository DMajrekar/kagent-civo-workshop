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

say "Two jobs. Attendees claim their credentials here with the passphrase from"
say "your slides and download a ready-made .env; and their daily report lands"
say "on their own page. Yours is /wall -- put it on the projector during step 05."

# ---------------------------------------------------------------- credentials
#
# relax.ai has no self-serve signup for events, so the hub hands out the keys.
# Drop them one per line in .state/relax-keys.txt -- a single key works too,
# everyone just shares it.
KEYS_FILE="$STATE/relax-keys.txt"
if [[ ! -s "$KEYS_FILE" ]]; then
  warn "no model keys found at $KEYS_FILE"
  note "put the keys from the relax.ai team there, one per line, then re-run."
  note "the handout page will refuse to issue anything until you do."
  : > "$KEYS_FILE"; chmod 600 "$KEYS_FILE"
fi
NKEYS=$(grep -cve '^\s*$' -e '^\s*#' "$KEYS_FILE" 2>/dev/null || echo 0)

# The passphrase goes on a slide, so make it typeable rather than random noise.
PASS_FILE="$STATE/join-passphrase"
if [[ -n "${JOIN_PASSPHRASE-}" ]]; then
  printf '%s' "$JOIN_PASSPHRASE" > "$PASS_FILE"
elif [[ ! -s "$PASS_FILE" ]]; then
  printf 'kagent-%s-%04d' "$(date +%b | tr '[:upper:]' '[:lower:]')" "$RANDOM" > "$PASS_FILE"
fi
chmod 600 "$PASS_FILE"
PASSPHRASE="$(cat "$PASS_FILE")"

# hub-08 rewrites the MCP endpoint with an https URL; a re-run picks that up.
MCP_URL="$(cat "$STATE/mcp-endpoint" 2>/dev/null || true)"

# PUBLIC_URL is this service's own address, which it does not know yet on a
# first LoadBalancer run. Resolve what we can now and reconcile after apply --
# reading it from the state file bakes in whatever the *previous* run wrote.
if kubectl -n "$NS" get ingress wall >/dev/null 2>&1; then
  PUB_URL="https://$(kubectl -n "$NS" get ingress wall -o jsonpath='{.spec.rules[0].host}')"
else
  PUB_URL=""
fi

ok "$NKEYS model key(s) in the pool"
note "passphrase for your slides: $PASSPHRASE"

run_quiet "kubectl -n '$NS' create secret generic workshop-credentials \
  --from-file=relax-keys.txt='$KEYS_FILE' \
  --from-file=mcp-tokens.txt='$STATE/mcp-tokens.txt' \
  --from-literal=join-passphrase='$PASSPHRASE' \
  --dry-run=client -o yaml | kubectl apply -f -"

run_quiet "kubectl -n '$NS' create configmap webhook-sink \
  --from-file=sink.py='$HERE/sink.py' \
  --dry-run=client -o yaml | kubectl apply -f -"

# If hub-08 has already put an ingress in front of this, do not hand it back a
# LoadBalancer of its own -- that silently resurrects a billing Civo LB and
# leaves two ways in, one of them unencrypted.
if [[ -n "$PUB_URL" ]]; then
  SINK_SVC_TYPE=ClusterIP
  note "ingress 'wall' exists — keeping the Service internal and using $PUB_URL"
else
  SINK_SVC_TYPE=LoadBalancer
fi

cat > "$STATE/sink.yaml" <<YAML
# The claim ledger is the one piece of state here that genuinely must survive a
# restart. Report history can live in browsers because losing it is harmless; a
# lost ledger means re-issuing credentials people already hold.
apiVersion: v1
kind: PersistentVolumeClaim
metadata: { name: webhook-sink-data, namespace: ${NS} }
spec:
  accessModes: [ReadWriteOnce]
  resources: { requests: { storage: 1Gi } }
---
apiVersion: apps/v1
kind: Deployment
metadata: { name: webhook-sink, namespace: ${NS} }
spec:
  replicas: 1        # single writer for the ledger; no reason to scale this
  strategy: { type: Recreate }   # RWO volume: the old pod must go first
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
            - { name: SECRETS_DIR, value: "/secrets" }
            - { name: LEDGER_PATH, value: "/data/ledger.json" }
            - { name: MCP_ENDPOINT, value: "${MCP_URL}" }
            - { name: PUBLIC_URL, value: "${PUB_URL}" }
            - name: JOIN_PASSPHRASE
              valueFrom:
                secretKeyRef: { name: workshop-credentials, key: join-passphrase }
          ports: [{ containerPort: 8080 }]
          volumeMounts:
            - { name: app, mountPath: /app }
            - { name: secrets, mountPath: /secrets, readOnly: true }
            - { name: data, mountPath: /data }
          readinessProbe:
            httpGet: { path: /healthz, port: 8080 }
          resources:
            requests: { cpu: 20m, memory: 48Mi }
            limits:   { memory: 192Mi }
      volumes:
        - name: app
          configMap: { name: webhook-sink }
        - name: secrets
          secret: { secretName: workshop-credentials }
        - name: data
          persistentVolumeClaim: { claimName: webhook-sink-data }
---
apiVersion: v1
kind: Service
metadata: { name: webhook-sink, namespace: ${NS} }
spec:
  type: ${SINK_SVC_TYPE}
  selector: { app: webhook-sink }
  ports: [{ name: http, port: 80, targetPort: 8080 }]
YAML

run "kubectl apply -f '$STATE/sink.yaml'"
run "kubectl -n '$NS' rollout status deploy/webhook-sink --timeout=300s"

if [[ "$SINK_SVC_TYPE" == "ClusterIP" ]]; then
  SINK_URL="$PUB_URL"
else
  wait_for "LoadBalancer to get an address" 600 \
    "[[ -n \"\$(kubectl -n '$NS' get svc webhook-sink -o jsonpath='{.status.loadBalancer.ingress[0].ip}')\" ]]"
  SINK_IP=$(kubectl -n "$NS" get svc webhook-sink -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
  SINK_URL="http://${SINK_IP}"
fi
echo "$SINK_URL" > "$STATE/sink-endpoint"

# Every .env the handout issues embeds this URL, so if the running pod is
# holding a different one, fix it now rather than issuing broken webhook URLs.
RUNNING_URL=$(kubectl -n "$NS" get deploy webhook-sink \
  -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="PUBLIC_URL")].value}' 2>/dev/null || true)
if [[ "$RUNNING_URL" != "$SINK_URL" ]]; then
  note "updating PUBLIC_URL: '${RUNNING_URL:-unset}' -> '$SINK_URL'"
  PUB_URL="$SINK_URL"
  sed -i "s|{ name: PUBLIC_URL, value: \".*\" }|{ name: PUBLIC_URL, value: \"$SINK_URL\" }|" "$STATE/sink.yaml"
  run "kubectl apply -f '$STATE/sink.yaml'"
  run "kubectl -n '$NS' rollout status deploy/webhook-sink --timeout=300s"
fi

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

say ""
say "4. The credential handout refuses a wrong passphrase."
JCODE=$(curl -sS -o /dev/null -w '%{http_code}' -XPOST "$SINK_URL/api/join" \
  -H 'Content-Type: application/json' -d '{"passphrase":"definitely-wrong","name":"probe"}' || echo 000)
if [[ "$NKEYS" -eq 0 ]]; then
  [[ "$JCODE" == "403" || "$JCODE" == "503" ]] && ok "handout is refusing requests (no keys loaded yet)" \
    || { fail "expected 403/503 from the handout, got $JCODE"; exit 1; }
else
  [[ "$JCODE" == "403" ]] && ok "403 for a wrong passphrase" \
    || { fail "expected 403 for a wrong passphrase, got $JCODE"; exit 1; }
fi

printf '\n'
ok "The wall is live."
note "credentials: $SINK_URL/join     <- this goes on your slides"
note "passphrase:  $PASSPHRASE"
note "attendees:   $SINK_URL"
note "projector:   $SINK_URL/wall"
if [[ "$SINK_URL" == https://* ]]; then
  ok "served over TLS via the ingress"
  note "next:  step-05"
else
  warn "Plain HTTP, like the MCP endpoint — hub-08 fixes both."
  note "This page hands out credentials, so do not put it on a slide until"
  note "hub-08 has run."
  note "next:  make hub-08   (TLS), then re-run hub-07"
fi
