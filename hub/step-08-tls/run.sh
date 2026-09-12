#!/usr/bin/env bash
# title: Put TLS in front of the public endpoints
#
# Until this runs, the MCP endpoint and the wall are plain HTTP and every
# attendee's bearer token crosses the internet in clear text.
#
# Hostnames default to sslip.io derived from the ingress IP, so this works with
# no DNS setup at all. If you own a domain, point a wildcard (or two A records)
# at the ingress IP and set HUB_DOMAIN — the card reads better for it.
#
#   make hub-08
#   HUB_DOMAIN=workshop.example.com make hub-08
source "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib.sh"

STATE="$REPO_ROOT/.state"
export KUBECONFIG="$STATE/hub.kubeconfig"
[[ -f "$KUBECONFIG" ]] || { fail "no hub kubeconfig — run 'make hub-01' first"; exit 1; }
NS="${OBS_NAMESPACE:-observability}"
ACME_EMAIL="${ACME_EMAIL:-${USER_EMAIL:-admin@example.com}}"

banner "Hub — step 08: TLS"

say "Two public endpoints are currently plain HTTP: the MCP server, which"
say "attendees authenticate to with a bearer token, and the wall. Tokens in"
say "clear text is not a thing to demonstrate to a room of engineers."

# --------------------------------------------------------------- ingress
run "helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx --force-update >/dev/null && \
     helm repo add jetstack https://charts.jetstack.io --force-update >/dev/null && \
     helm repo update >/dev/null && echo ok"

run "helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace \
  --set controller.service.type=LoadBalancer \
  --set controller.replicaCount=1 \
  --set controller.resources.requests.cpu=50m \
  --set controller.resources.requests.memory=128Mi \
  --wait --timeout 10m"

wait_for "the ingress LoadBalancer to get an address" 600 \
  "[[ -n \"\$(kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')\" ]]"
ING_IP=$(kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
ok "ingress address: $ING_IP"

if [[ -n "${HUB_DOMAIN-}" ]]; then
  MCP_HOST="mcp.${HUB_DOMAIN}"
  WALL_HOST="wall.${HUB_DOMAIN}"
  warn "Point these at $ING_IP in DNS before continuing, or the ACME challenge fails:"
  note "  $MCP_HOST  ->  $ING_IP"
  note "  $WALL_HOST ->  $ING_IP"
  pause "confirm DNS is in place"
else
  DASHED="${ING_IP//./-}"
  MCP_HOST="mcp-${DASHED}.sslip.io"
  WALL_HOST="wall-${DASHED}.sslip.io"
  note "no HUB_DOMAIN set — using sslip.io, which needs no DNS setup"
fi
say ""
note "MCP:  https://$MCP_HOST/mcp"
note "wall: https://$WALL_HOST/"

# Fail early and clearly if the name does not resolve to the ingress.
for h in "$MCP_HOST" "$WALL_HOST"; do
  GOT=$(python3 -c "import socket;print(socket.gethostbyname('$h'))" 2>/dev/null || echo "")
  if [[ "$GOT" != "$ING_IP" ]]; then
    fail "$h resolves to '${GOT:-nothing}', not $ING_IP"
    note "Let's Encrypt validates over HTTP-01, so this must resolve first."
    exit 1
  fi
done
ok "both hostnames resolve to the ingress"

# ------------------------------------------------------------ cert-manager
run "helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager --create-namespace \
  --set crds.enabled=true \
  --set resources.requests.cpu=20m \
  --wait --timeout 10m"

cat > "$STATE/clusterissuer.yaml" <<YAML
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: ${ACME_EMAIL}
    privateKeySecretRef: { name: letsencrypt-account-key }
    solvers:
      - http01:
          ingress: { class: nginx }
YAML
run "kubectl apply -f '$STATE/clusterissuer.yaml'"
wait_for "the ACME account to register" 300 \
  "[[ \"\$(kubectl get clusterissuer letsencrypt -o jsonpath='{.status.conditions[?(@.type==\"Ready\")].status}' 2>/dev/null)\" == 'True' ]]"

# ---------------------------------------------------------------- ingresses
cat > "$STATE/ingress.yaml" <<YAML
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: mcp
  namespace: ${NS}
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt
    # MCP Streamable HTTP holds responses open as SSE. Buffering here would
    # make an agent look hung for minutes.
    nginx.ingress.kubernetes.io/proxy-buffering: "off"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "3600"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "3600"
    nginx.ingress.kubernetes.io/proxy-body-size: "8m"
spec:
  ingressClassName: nginx
  tls:
    - hosts: [${MCP_HOST}]
      secretName: mcp-tls
  rules:
    - host: ${MCP_HOST}
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: mcp-public
                port: { number: 80 }
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: wall
  namespace: ${NS}
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt
    nginx.ingress.kubernetes.io/proxy-body-size: "1m"
spec:
  ingressClassName: nginx
  tls:
    - hosts: [${WALL_HOST}]
      secretName: wall-tls
  rules:
    - host: ${WALL_HOST}
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: webhook-sink
                port: { number: 80 }
YAML
run "kubectl apply -f '$STATE/ingress.yaml'"

say ""
say "Let's Encrypt now validates each hostname over HTTP-01. This usually takes"
say "under a minute per certificate."
for c in mcp-tls wall-tls; do
  wait_for "certificate $c to be issued" 600 \
    "[[ \"\$(kubectl -n '$NS' get certificate $c -o jsonpath='{.status.conditions[?(@.type==\"Ready\")].status}' 2>/dev/null)\" == 'True' ]]"
done
run "kubectl -n '$NS' get certificate"

# --------------------------------------------------------------- verify
say ""
say "Verify over HTTPS, including that the auth boundary still holds through"
say "the new front door."
MCP_URL="https://${MCP_HOST}/mcp"
WALL_URL="https://${WALL_HOST}"
TOKEN=$(awk 'NR==1{print $2}' "$STATE/mcp-tokens.txt")

wait_for "https to answer" 300 "curl -sf -o /dev/null '$WALL_URL/healthz'"

CODE=$(curl -sS -o /dev/null -w '%{http_code}' -XPOST "$MCP_URL" -H 'Content-Type: application/json' -d '{}' || echo 000)
[[ "$CODE" == "401" ]] && ok "unauthenticated MCP request still rejected (401) over TLS" \
  || { fail "expected 401 without a token, got $CODE"; exit 1; }

MCP_TOKEN="$TOKEN" run "python3 '$REPO_ROOT/scripts/mcp-probe.py' '$MCP_URL' --token-env MCP_TOKEN --quiet \
  --call list_loki_label_values \
  --args '{\"datasourceUid\":\"workshop-loki\",\"labelName\":\"service\"}'"

say ""
say "Retire the two bare LoadBalancers -- everything goes through the ingress"
say "now, and an idle Civo LoadBalancer still bills."
run "kubectl -n '$NS' patch svc mcp-public   -p '{\"spec\":{\"type\":\"ClusterIP\"}}'"
run "kubectl -n '$NS' patch svc webhook-sink -p '{\"spec\":{\"type\":\"ClusterIP\"}}'"

echo "$MCP_URL"  > "$STATE/mcp-endpoint"
echo "$WALL_URL" > "$STATE/sink-endpoint"

printf '\n'
ok "Both public endpoints are HTTPS."
note "MCP_ENDPOINT=$MCP_URL"
note "wall:      $WALL_URL"
note "projector: $WALL_URL/wall"
note "these go on the workshop cards"
printf '\n'
warn "Re-run 'make hub-07' now."
note "The credential handout bakes MCP_ENDPOINT and the webhook URL into every"
note ".env it issues, and it is still holding the old http:// addresses."
