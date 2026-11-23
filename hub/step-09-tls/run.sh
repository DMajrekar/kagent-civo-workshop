#!/usr/bin/env bash
# title: Public HTTPS addresses for the CTF, Grafana and kagent
#
# Three hostnames, one ingress, certificates from Let's Encrypt:
#
#   ctf-…     the page players join and play on
#   logs-…    Grafana, anonymous and read-only (round one)
#   kagent-…  the kagent dashboard (round two), where every request is first
#             shown to the CTF app, which says who the player is and whether
#             kagent is unlocked yet
#
# The MCP endpoint is deliberately not here. Agents run inside this cluster
# now, so nothing outside it needs to reach the logs except through Grafana.
#
# Hostnames default to sslip.io derived from the ingress IP, so this works with
# no DNS setup at all. If you own a domain, point a wildcard at the ingress IP
# and set HUB_DOMAIN — a QR code hides the URL, but the address bar does not.
#
#   make hub-09
#   HUB_DOMAIN=workshop.example.com make hub-09
source "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib.sh"

STATE="$REPO_ROOT/.state"
export KUBECONFIG="$STATE/hub.kubeconfig"
[[ -f "$KUBECONFIG" ]] || { fail "no hub kubeconfig — run 'make hub-01' first"; exit 1; }
NS="${OBS_NAMESPACE:-observability}"
ACME_EMAIL="${ACME_EMAIL:-${USER_EMAIL:-admin@example.com}}"

banner "Hub — step 09: public addresses and TLS"

kubectl -n "$NS" get svc ctf >/dev/null 2>&1 || { fail "no CTF app — run 'make hub-07' first"; exit 1; }
kubectl -n kagent get svc kagent-guard >/dev/null 2>&1 || { fail "no kagent guard — run 'make hub-08' first"; exit 1; }

say "Everything the room touches goes through here. Players are on mobile"
say "data, so this is the whole of their path in: one LoadBalancer, three names."

# --------------------------------------------------------------- ingress
run "helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx --force-update >/dev/null && \
     helm repo add jetstack https://charts.jetstack.io --force-update >/dev/null && \
     helm repo update >/dev/null && echo ok"

run "helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace \
  --version '${INGRESS_NGINX_VERSION:-4.15.1}' \
  --set controller.service.type=LoadBalancer \
  --set controller.replicaCount=2 \
  --set controller.resources.requests.cpu=100m \
  --set controller.resources.requests.memory=128Mi \
  --wait --timeout 10m"

wait_for "the ingress LoadBalancer to get an address" 600 \
  "[[ -n \"\$(kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')\" ]]"
ING_IP=$(kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
ok "ingress address: $ING_IP"

if [[ -n "${HUB_DOMAIN-}" ]]; then
  CTF_HOST="ctf.${HUB_DOMAIN}"
  GRAF_HOST="logs.${HUB_DOMAIN}"
  KAGENT_HOST="kagent.${HUB_DOMAIN}"
  warn "Point these at $ING_IP in DNS before continuing, or the ACME challenge fails:"
  for h in "$CTF_HOST" "$GRAF_HOST" "$KAGENT_HOST"; do note "  $h  ->  $ING_IP"; done
  pause "confirm DNS is in place"
else
  DASHED="${ING_IP//./-}"
  CTF_HOST="ctf-${DASHED}.sslip.io"
  GRAF_HOST="logs-${DASHED}.sslip.io"
  KAGENT_HOST="kagent-${DASHED}.sslip.io"
  note "no HUB_DOMAIN set — using sslip.io, which needs no DNS setup"
fi
say ""
note "ctf:     https://$CTF_HOST/"
note "grafana: https://$GRAF_HOST/   (anonymous, read-only)"
note "kagent:  https://$KAGENT_HOST/ (players only, from round two)"

# Fail early and clearly if a name does not resolve to the ingress.
for h in "$CTF_HOST" "$GRAF_HOST" "$KAGENT_HOST"; do
  GOT=$(python3 -c "import socket;print(socket.gethostbyname('$h'))" 2>/dev/null || echo "")
  if [[ "$GOT" != "$ING_IP" ]]; then
    fail "$h resolves to '${GOT:-nothing}', not $ING_IP"
    note "Let's Encrypt validates over HTTP-01, so this must resolve first."
    exit 1
  fi
done
ok "all three hostnames resolve to the ingress"

# ------------------------------------------------------------ cert-manager
run "helm upgrade --install cert-manager jetstack/cert-manager \
  --namespace cert-manager --create-namespace \
  --version '${CERT_MANAGER_VERSION:-v1.21.2}' \
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
#
# The kagent host is the interesting one. `auth-url` makes nginx ask the CTF
# app about every request before passing it on. A 200 comes back with an
# X-User-Id header, which nginx then sets on the request -- overwriting
# anything the browser sent, so a player cannot choose their own identity. A
# 401 means "not a player" or "round two has not started", and sends the
# browser back to the CTF page.
#
# Two backends on that host: /api goes to the guard, everything else to the
# dashboard. Sending /api to the dashboard would also work -- it proxies /api
# itself -- but straight to the controller, around the guard.
cat > "$STATE/ingress.yaml" <<YAML
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ctf
  namespace: ${NS}
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt
    nginx.ingress.kubernetes.io/proxy-body-size: "64k"
spec:
  ingressClassName: nginx
  tls:
    - hosts: [${CTF_HOST}]
      secretName: ctf-tls
  rules:
    - host: ${CTF_HOST}
      http:
        paths:
          - path: /
            pathType: Prefix
            backend: { service: { name: ctf, port: { number: 80 } } }
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: grafana
  namespace: ${NS}
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt
    nginx.ingress.kubernetes.io/proxy-body-size: "2m"
spec:
  ingressClassName: nginx
  tls:
    - hosts: [${GRAF_HOST}]
      secretName: grafana-tls
  rules:
    - host: ${GRAF_HOST}
      http:
        paths:
          - path: /
            pathType: Prefix
            backend: { service: { name: grafana, port: { number: 80 } } }
---
# The CTF app, reachable by name from the kagent namespace: an Ingress can
# only route to Services in its own namespace.
apiVersion: v1
kind: Service
metadata: { name: ctf-gateway, namespace: kagent }
spec:
  type: ExternalName
  externalName: ctf.${NS}.svc.cluster.local
  ports: [{ name: http, port: 80 }]
---
# /gw/enter is where a player arrives from the CTF page carrying a short-lived
# token, and leaves with a cookie for this host. It cannot itself be behind
# the auth check -- nobody has the cookie yet.
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: kagent-enter
  namespace: kagent
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt
spec:
  ingressClassName: nginx
  tls:
    - hosts: [${KAGENT_HOST}]
      secretName: kagent-tls
  rules:
    - host: ${KAGENT_HOST}
      http:
        paths:
          - path: /gw/enter
            pathType: Exact
            backend: { service: { name: ctf-gateway, port: { number: 80 } } }
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: kagent
  namespace: kagent
  annotations:
    nginx.ingress.kubernetes.io/auth-url: "http://ctf.${NS}.svc.cluster.local/gw/auth"
    nginx.ingress.kubernetes.io/auth-response-headers: "X-User-Id"
    nginx.ingress.kubernetes.io/auth-signin: "https://${CTF_HOST}/"
    # An agent's answer streams back over tens of seconds. Buffering it would
    # make every question look like it had hung.
    nginx.ingress.kubernetes.io/proxy-buffering: "off"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "1800"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "1800"
    nginx.ingress.kubernetes.io/proxy-body-size: "1m"
spec:
  ingressClassName: nginx
  tls:
    - hosts: [${KAGENT_HOST}]
      secretName: kagent-tls
  rules:
    - host: ${KAGENT_HOST}
      http:
        paths:
          - path: /api
            pathType: Prefix
            backend: { service: { name: kagent-guard, port: { number: 8080 } } }
          - path: /
            pathType: Prefix
            backend: { service: { name: kagent-ui, port: { number: 8080 } } }
YAML
run "kubectl apply -f '$STATE/ingress.yaml'"

# Left over from the build-your-own-cluster format, where attendee clusters
# reached the logs over the internet. Nothing outside needs that now.
if kubectl -n "$NS" get ingress mcp >/dev/null 2>&1; then
  note "removing the public MCP ingress — agents reach the logs in-cluster now"
  run "kubectl -n '$NS' delete ingress mcp --ignore-not-found"
fi
if kubectl -n "$NS" get ingress wall >/dev/null 2>&1; then
  run "kubectl -n '$NS' delete ingress wall --ignore-not-found"
fi

say ""
say "Let's Encrypt now validates each hostname over HTTP-01. This usually takes"
say "under a minute per certificate."
for pair in "$NS/ctf-tls" "$NS/grafana-tls" "kagent/kagent-tls"; do
  wait_for "certificate ${pair#*/} to be issued" 600 \
    "[[ \"\$(kubectl -n '${pair%/*}' get certificate '${pair#*/}' -o jsonpath='{.status.conditions[?(@.type==\"Ready\")].status}' 2>/dev/null)\" == 'True' ]]"
done

CTF_URL="https://${CTF_HOST}"
KAGENT_URL="https://${KAGENT_HOST}"
echo "$CTF_URL"    > "$STATE/ctf-endpoint"
echo "$KAGENT_URL" > "$STATE/kagent-endpoint"
echo "https://${GRAF_HOST}" > "$STATE/grafana-endpoint"

# A deep link straight into Explore on the workshop Loki datasource, last 7
# days. Finding the Explore button is not the exercise; knowing what to ask
# once you are there is.
python3 - "https://${GRAF_HOST}" > "$STATE/grafana-explore-url" <<'PYEOF'
import json, sys, urllib.parse
base = sys.argv[1]
pane = {"a": {"datasource": "workshop-loki",
              "queries": [{"refId": "A",
                           "datasource": {"type": "loki", "uid": "workshop-loki"},
                           "expr": '{env="production"}'}],
              "range": {"from": "now-7d", "to": "now"}}}
print(f"{base}/explore?schemaVersion=1&orgId=1&panes=" + urllib.parse.quote(json.dumps(pane)))
PYEOF

# --------------------------------------------------------------- verify
say ""
say "Verify from the outside, the way a phone will see it."
wait_for "https to answer" 300 "curl -sf -o /dev/null '$CTF_URL/healthz'"

BAD=0
check() {
  if [[ "$2" == "$3" ]]; then printf '  %s%s✓%s %s\n' "$BOLD" "$GREEN" "$RESET" "$1"
  else printf '  %s%s✗%s %s (expected %s, got %s)\n' "$BOLD" "$RED" "$RESET" "$1" "$2" "$3"; BAD=1; fi
}
code() { curl -sS -o /dev/null -w '%{http_code}' --max-time 20 "$@" || echo 000; }

check "the CTF page answers"                       200 "$(code "$CTF_URL/")"
check "Grafana answers without a login"            200 "$(code "https://${GRAF_HOST}/api/health")"
check "kagent turns a stranger away"               302 "$(code "$KAGENT_URL/")"
check "…and its API too"                           302 "$(code "$KAGENT_URL/api/agents")"
check "a made-up identity header does not help"    302 "$(code "$KAGENT_URL/api/agents" -H 'X-User-Id: admin@kagent.dev')"
check "a bad entry token gets no cookie"           302 "$(code "$KAGENT_URL/gw/enter?t=forged&to=/")"
if (( BAD )); then
  fail "the public side is not behaving — do not put the QR code up yet"
  exit 1
fi

# Internal now. An idle Civo LoadBalancer still bills, and the MCP one was
# also a second, token-only way in to the logs.
for svc in mcp-public ctf; do
  T=$(kubectl -n "$NS" get svc "$svc" -o jsonpath='{.spec.type}' 2>/dev/null || true)
  [[ "$T" == "LoadBalancer" ]] && run "kubectl -n '$NS' patch svc $svc -p '{\"spec\":{\"type\":\"ClusterIP\"}}'"
done
kubectl -n "$NS" get svc webhook-sink >/dev/null 2>&1 && \
  note "the old webhook-sink is still deployed — 'kubectl -n $NS delete deploy,svc,pvc -l app=webhook-sink' when you are sure"

# The CTF app hands out these addresses, so it needs telling. Re-running its
# step is the one way that cannot drift from a first install.
say ""
say "Last: tell the CTF app its public addresses."
DEMO_AUTO=1 bash "$REPO_ROOT/hub/step-07-ctf/run.sh" >"$STATE/hub-07-rerun.log" 2>&1 \
  && ok "CTF app updated" \
  || { fail "re-running hub-07 failed — see $STATE/hub-07-rerun.log"; exit 1; }

printf '\n'
ok "Everything the room needs is public and on HTTPS."
note "players (QR code): $CTF_URL"
note "projector:         $CTF_URL/board"
note "you:               $CTF_URL/admin     key: $(cat "$STATE/ctf-admin-key" 2>/dev/null)"
note "grafana:           $(cat "$STATE/grafana-explore-url")"
printf '\n'
say "Before the day, play it yourself on a phone on mobile data, end to end:"
say "join, start round one from /admin, solve a flag in Grafana, start round"
say "two, 'make agent-01', and ask the agent something. docs/RUNSHEET.md has"
say "the full rehearsal list."
