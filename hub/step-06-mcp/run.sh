#!/usr/bin/env bash
# title: Expose the MCP endpoint
#
# This is the piece every attendee cluster connects to. Three parts:
#   mcp-grafana   talks MCP, reads Loki through Grafana's API, read-only
#   auth proxy    checks a per-attendee bearer token
#   LoadBalancer  a public address
#
# Per-attendee tokens rather than one shared secret: it costs nothing extra on
# the workshop card, and it is the difference between revoking one token and
# breaking the endpoint for everyone for the three weeks the hub stays up.
source "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib.sh"

STATE="$REPO_ROOT/.state"
export KUBECONFIG="$STATE/hub.kubeconfig"
[[ -f "$KUBECONFIG" ]] || { fail "no hub kubeconfig — run 'make hub-01' first"; exit 1; }
NS="${OBS_NAMESPACE:-observability}"
N_TOKENS="${ATTENDEE_COUNT:-60}"   # 50 attendees plus spares
# Digest-pinned. ":latest" moved under us would change the tool list an agent
# sees, with no version number anywhere to explain why.
MCP_IMAGE="${MCP_IMAGE:-mcp/grafana@sha256:9362bcf6aa0e44e61f645b905cec03fb346a946a34a4dafecd7f3e28d3724014}"

banner "Hub — step 06: the MCP endpoint"

# ------------------------------------------------ Grafana service account
say "mcp-grafana authenticates to Grafana with a service account token, so"
say "first mint one. Viewer role: the MCP server is started with --disable-write"
say "but the token should not be able to mutate anything either way."

GRAFANA_PW="$(cat "$STATE/grafana-admin-password")"
trap cleanup_port_forwards EXIT
port_forward "$NS" svc/grafana 3000:80
wait_for "Grafana to be healthy" 120 "curl -sf -o /dev/null http://127.0.0.1:3000/api/health"

SA_TOKEN_FILE="$STATE/grafana-sa-token"
if [[ ! -s "$SA_TOKEN_FILE" ]]; then
  SA_ID=$(curl -sS -u "admin:$GRAFANA_PW" -X POST http://127.0.0.1:3000/api/serviceaccounts \
    -H 'Content-Type: application/json' \
    -d '{"name":"mcp-grafana","role":"Viewer","isDisabled":false}' | jq -r '.id // empty')
  if [[ -z "$SA_ID" ]]; then
    SA_ID=$(curl -sS -u "admin:$GRAFANA_PW" \
      "http://127.0.0.1:3000/api/serviceaccounts/search?query=mcp-grafana" \
      | jq -r '.serviceAccounts[0].id // empty')
  fi
  [[ -n "$SA_ID" ]] || { fail "could not create or find the mcp-grafana service account"; exit 1; }
  curl -sS -u "admin:$GRAFANA_PW" -X POST \
    "http://127.0.0.1:3000/api/serviceaccounts/${SA_ID}/tokens" \
    -H 'Content-Type: application/json' \
    -d "{\"name\":\"mcp-$(date +%s)\"}" | jq -rj '.key' > "$SA_TOKEN_FILE"
  chmod 600 "$SA_TOKEN_FILE"
fi
# Strip any trailing newline: it travels into an Authorization header, and the
# resulting "invalid header field value" surfaces as a tool error, not a
# credential error, which sends you looking in the wrong place entirely.
if [[ -s "$SA_TOKEN_FILE" ]]; then
  printf '%s' "$(tr -d '\r\n' < "$SA_TOKEN_FILE")" > "$SA_TOKEN_FILE.tmp" && mv "$SA_TOKEN_FILE.tmp" "$SA_TOKEN_FILE"
  chmod 600 "$SA_TOKEN_FILE"
fi
grep -q . "$SA_TOKEN_FILE" || { fail "empty Grafana service account token"; exit 1; }
ok "Grafana service account token ready ($SA_TOKEN_FILE)"

# ------------------------------------------------------- attendee tokens
# Top up rather than regenerate: existing tokens may already be in someone's
# .env, and rewriting the file would silently lock them out.
TOKENS_FILE="$STATE/mcp-tokens.txt"
touch "$TOKENS_FILE"; chmod 600 "$TOKENS_FILE"
HAVE=$(grep -c . "$TOKENS_FILE" 2>/dev/null || echo 0)
if (( HAVE < N_TOKENS )); then
  for (( i = HAVE + 1; i <= N_TOKENS; i++ )); do
    printf 'attendee-%02d %s\n' "$i" "$(head -c 24 /dev/urandom | base64 | tr -d '/+=' | head -c 28)" >> "$TOKENS_FILE"
  done
  (( HAVE > 0 )) && note "topped up from $HAVE to $N_TOKENS tokens (existing ones kept)"
fi
ok "$(wc -l < "$TOKENS_FILE") attendee tokens ($TOKENS_FILE)"

run_quiet "kubectl -n '$NS' create secret generic mcp-grafana-auth \
  --from-file=GRAFANA_SERVICE_ACCOUNT_TOKEN='$SA_TOKEN_FILE' \
  --dry-run=client -o yaml | kubectl apply -f -"

# nginx map of valid bearer values. Regenerated from the token file each run,
# so revoking a token is: delete the line, re-run this step.
{
  echo 'map $http_authorization $mcp_token_ok {'
  echo '    default 0;'
  while read -r name tok; do
    [[ -n "$tok" ]] && printf '    "Bearer %s" 1;   # %s\n' "$tok" "$name"
  done < "$TOKENS_FILE"
  echo '}'
} > "$STATE/mcp-tokens.conf"

cat > "$STATE/mcp-proxy.conf" <<'NGINX'
server {
    listen 8080;

    # Health check for the LoadBalancer. Deliberately unauthenticated and
    # deliberately says nothing about the service behind it.
    location = /healthz {
        access_log off;
        return 200 "ok\n";
    }

    location / {
        if ($mcp_token_ok = 0) {
            add_header Content-Type application/json always;
            return 401 '{"error":"invalid or missing bearer token"}';
        }
        proxy_pass http://mcp-grafana:8000;
        proxy_http_version 1.1;

        # MCP Streamable HTTP can hold a response open as an SSE stream.
        # Buffering here would make an agent look hung for minutes.
        proxy_buffering off;
        proxy_cache off;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
        chunked_transfer_encoding on;

        # mcp-grafana validates the Host header (DNS-rebinding protection).
        # Rewrite it to a fixed internal value and allowlist exactly that,
        # rather than disabling validation with "*".
        proxy_set_header Host mcp-grafana.internal;
        proxy_set_header Connection "";
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
NGINX

run_quiet "kubectl -n '$NS' create configmap mcp-proxy-conf \
  --from-file=tokens.conf='$STATE/mcp-tokens.conf' \
  --from-file=proxy.conf='$STATE/mcp-proxy.conf' \
  --dry-run=client -o yaml | kubectl apply -f -"

# If hub-08 has already fronted this with an ingress, do not hand it back a
# LoadBalancer of its own. Re-running this step afterwards would otherwise
# resurrect a billing Civo LB, reopen an unencrypted way in, and overwrite
# .state/mcp-endpoint with a plain-http address that the credential handout
# then issues to everyone.
if MCP_ING_HOST=$(kubectl -n "$NS" get ingress mcp -o jsonpath='{.spec.rules[0].host}' 2>/dev/null) \
   && [[ -n "$MCP_ING_HOST" ]]; then
  MCP_SVC_TYPE=ClusterIP
  note "ingress 'mcp' exists — keeping the Service internal and using https://$MCP_ING_HOST"
else
  MCP_SVC_TYPE=LoadBalancer
  MCP_ING_HOST=""
fi

cat > "$STATE/mcp.yaml" <<YAML
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
          image: ${MCP_IMAGE}
          args:
            - "-t"
            - "streamable-http"
            - "--address"
            - "0.0.0.0:8000"
            - "--disable-write"
            - "-allowed-hosts"
            - "mcp-grafana.internal"
            # Keep only Loki plus datasource discovery. The default 52 tools
            # give a small model far too many plausible wrong turns, and every
            # one it takes costs a turn on stage.
            - "-disable-admin"
            - "-disable-alerting"
            - "-disable-annotations"
            - "-disable-api"
            - "-disable-asserts"
            - "-disable-athena"
            - "-disable-clickhouse"
            - "-disable-cloudwatch"
            - "-disable-config"
            - "-disable-dashboard"
            - "-disable-elasticsearch"
            - "-disable-examples"
            - "-disable-folder"
            - "-disable-graphite"
            - "-disable-incident"
            - "-disable-influxdb"
            - "-disable-navigation"
            - "-disable-oncall"
            - "-disable-plugin"
            - "-disable-prometheus"
            - "-disable-provisioning"
            - "-disable-proxied"
            - "-disable-pyroscope"
            - "-disable-quickwit"
            - "-disable-rendering"
            - "-disable-runpanelquery"
            - "-disable-search"
            - "-disable-sift"
            - "-disable-snapshot"
            - "-disable-snowflake"
          env:
            - { name: GRAFANA_URL, value: "http://grafana.${NS}.svc.cluster.local" }
            - name: GRAFANA_SERVICE_ACCOUNT_TOKEN
              valueFrom:
                secretKeyRef: { name: mcp-grafana-auth, key: GRAFANA_SERVICE_ACCOUNT_TOKEN }
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
---
apiVersion: apps/v1
kind: Deployment
metadata: { name: mcp-proxy, namespace: ${NS} }
spec:
  replicas: 2
  selector: { matchLabels: { app: mcp-proxy } }
  template:
    metadata:
      labels: { app: mcp-proxy }
      annotations:
        proxy/checksum: "$(sha256sum "$STATE/mcp-tokens.conf" "$STATE/mcp-proxy.conf" | sha256sum | cut -c1-16)"
    spec:
      containers:
        - name: nginx
          image: nginx:1.27-alpine
          ports: [{ containerPort: 8080 }]
          volumeMounts:
            - { name: conf, mountPath: /etc/nginx/conf.d/proxy.conf,  subPath: proxy.conf }
            - { name: conf, mountPath: /etc/nginx/conf.d/tokens.conf, subPath: tokens.conf }
          readinessProbe:
            httpGet: { path: /healthz, port: 8080 }
          resources:
            requests: { cpu: 20m, memory: 32Mi }
            limits:   { memory: 128Mi }
      volumes:
        - name: conf
          configMap: { name: mcp-proxy-conf }
---
apiVersion: v1
kind: Service
metadata: { name: mcp-public, namespace: ${NS} }
spec:
  type: ${MCP_SVC_TYPE}
  selector: { app: mcp-proxy }
  ports: [{ name: http, port: 80, targetPort: 8080 }]
YAML

run "kubectl apply -f '$STATE/mcp.yaml'"
run "kubectl -n '$NS' rollout status deploy/mcp-grafana --timeout=300s"
run "kubectl -n '$NS' rollout status deploy/mcp-proxy   --timeout=300s"

if [[ "$MCP_SVC_TYPE" == "ClusterIP" ]]; then
  MCP_URL="https://${MCP_ING_HOST}/mcp"
  LB_IP="$MCP_ING_HOST"
else
  wait_for "LoadBalancer to get an address" 600 \
    "[[ -n \"\$(kubectl -n '$NS' get svc mcp-public -o jsonpath='{.status.loadBalancer.ingress[0].ip}')\" ]]"
  LB_IP=$(kubectl -n "$NS" get svc mcp-public -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
  MCP_URL="http://${LB_IP}/mcp"
fi
echo "$MCP_URL" > "$STATE/mcp-endpoint"
ok "MCP endpoint: $MCP_URL"

# ------------------------------------------------------------- verification
say ""
say "Verifying. A 200 from curl is not evidence -- MCP is a JSON-RPC handshake,"
say "and a proxy can return 200 for a session it has actually broken. So do the"
say "handshake, and check the auth boundary in both directions."

FIRST_TOKEN=$(awk 'NR==1{print $2}' "$TOKENS_FILE")

HEALTH_BASE="${MCP_URL%/mcp}"
wait_for "endpoint to answer" 300 "curl -sf -o /dev/null '$HEALTH_BASE/healthz'"

say ""
say "1. No token must be refused."
CODE=$(curl -sS -o /dev/null -w '%{http_code}' -XPOST "$MCP_URL" -H 'Content-Type: application/json' -d '{}' || echo 000)
if [[ "$CODE" == "401" ]]; then ok "unauthenticated request rejected (401)"
else fail "expected 401 without a token, got $CODE"; exit 1; fi

say ""
say "2. A wrong token must be refused."
CODE=$(curl -sS -o /dev/null -w '%{http_code}' -XPOST "$MCP_URL" -H 'Authorization: Bearer not-a-real-token' -H 'Content-Type: application/json' -d '{}' || echo 000)
if [[ "$CODE" == "401" ]]; then ok "bad token rejected (401)"
else fail "expected 401 with a bad token, got $CODE"; exit 1; fi

say ""
say "3. A valid token must complete the MCP handshake and list tools."
MCP_TOKEN="$FIRST_TOKEN" run "python3 '$REPO_ROOT/scripts/mcp-probe.py' '$MCP_URL' --token-env MCP_TOKEN"

say ""
say "4. And an actual Loki query must return data through the whole path."
MCP_TOKEN="$FIRST_TOKEN" run "python3 '$REPO_ROOT/scripts/mcp-probe.py' '$MCP_URL' --token-env MCP_TOKEN --quiet \
  --call list_loki_label_values \
  --args '{\"datasourceUid\":\"workshop-loki\",\"labelName\":\"service\"}'"

printf '\n'
ok "The MCP endpoint is live and authenticated."
if [[ "$MCP_URL" == https://* ]]; then
  ok "served over TLS via the ingress"
else
warn "This is plain HTTP — bearer tokens cross the internet in clear text."
note "hub-08 puts TLS in front of it. Run that before handing the endpoint to"
note "anyone; do not print this URL on a workshop card."
fi
note "endpoint: $MCP_URL"
note "tokens:   $TOKENS_FILE"
note "next:  make hub-07   (the webhook wall), then hub-08 (TLS)"
