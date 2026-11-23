#!/usr/bin/env bash
# title: Build the slide deck and host it on the hub
#
# The deck is a React app, so it has to be built before it can be served, and
# the join QR code is baked in at build time. Rather than ask for Node or
# Docker on your laptop and a registry to push to, this builds it on the hub:
#
#   builder   a Node container that sits idle next to nginx. This step copies
#             slides/ into it and runs the build there.
#   web       nginx, serving whatever the last build produced.
#
# Both share one volume, so the deck survives a restart without rebuilding.
#
# Re-run this step after anything in slides/ changes -- including after
# `make record`, to get the recordings into the hosted deck.
source "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib.sh"

STATE="$REPO_ROOT/.state"
export KUBECONFIG="$STATE/hub.kubeconfig"
[[ -f "$KUBECONFIG" ]] || { fail "no hub kubeconfig — run 'make hub-01' first"; exit 1; }
NS=slides
NODE_IMAGE="${SLIDES_NODE_IMAGE:-node:22-alpine}"
WEB_IMAGE="${SLIDES_WEB_IMAGE:-nginxinc/nginx-unprivileged:1.27-alpine}"
CTF_URL="$(cat "$STATE/ctf-endpoint" 2>/dev/null || true)"
[[ -n "$CTF_URL" ]] || { fail "no CTF address yet — run 'make hub-09' first, the join QR code needs it"; exit 1; }

banner "Hub — step 10: the slide deck"

ING_IP=$(kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
[[ -n "$ING_IP" ]] || { fail "the ingress has no address — run 'make hub-09' first"; exit 1; }
if [[ -n "${HUB_DOMAIN-}" ]]; then
  HOST="slides.${HUB_DOMAIN}"
  warn "Point $HOST at $ING_IP in DNS before continuing."
  pause "confirm DNS is in place"
else
  HOST="slides-${ING_IP//./-}.sslip.io"
fi
note "deck:    https://$HOST/"
note "join QR: $CTF_URL"

cat > "$STATE/slides.yaml" <<YAML
apiVersion: v1
kind: Namespace
metadata: { name: ${NS} }
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata: { name: slides, namespace: ${NS} }
spec:
  accessModes: [ReadWriteOnce]
  resources: { requests: { storage: 2Gi } }
---
apiVersion: apps/v1
kind: Deployment
metadata: { name: slides, namespace: ${NS} }
spec:
  replicas: 1
  strategy: { type: Recreate }   # one volume, so never two pods at once
  selector: { matchLabels: { app: slides } }
  template:
    metadata: { labels: { app: slides } }
    spec:
      initContainers:
        # The web root has to exist before nginx mounts it.
        - name: init
          image: ${NODE_IMAGE}
          command: ["sh", "-c", "mkdir -p /work/live /work/src && chmod 755 /work /work/live"]
          volumeMounts: [{ name: work, mountPath: /work }]
      containers:
        - name: web
          image: ${WEB_IMAGE}
          ports: [{ containerPort: 8080 }]
          readinessProbe: { httpGet: { path: /healthz, port: 8080 } }
          volumeMounts:
            - { name: work, mountPath: /usr/share/nginx/html, subPath: live, readOnly: true }
            - { name: conf, mountPath: /etc/nginx/conf.d/default.conf, subPath: nginx.conf }
          resources: { requests: { cpu: 10m, memory: 16Mi }, limits: { memory: 128Mi } }
        - name: builder
          image: ${NODE_IMAGE}
          command: ["sleep", "infinity"]
          volumeMounts: [{ name: work, mountPath: /work }]
          resources: { requests: { cpu: 10m, memory: 32Mi }, limits: { memory: 2Gi } }
      volumes:
        - name: work
          persistentVolumeClaim: { claimName: slides }
        - name: conf
          configMap: { name: slides-nginx }
---
apiVersion: v1
kind: Service
metadata: { name: slides, namespace: ${NS} }
spec:
  selector: { app: slides }
  ports: [{ port: 80, targetPort: 8080 }]
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: slides
  namespace: ${NS}
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt
spec:
  ingressClassName: nginx
  tls:
    - hosts: [${HOST}]
      secretName: slides-tls
  rules:
    - host: ${HOST}
      http:
        paths:
          - path: /
            pathType: Prefix
            backend: { service: { name: slides, port: { number: 80 } } }
YAML

run "kubectl create namespace $NS --dry-run=client -o yaml | kubectl apply -f -"
run "kubectl -n $NS create configmap slides-nginx \
  --from-file=nginx.conf='$REPO_ROOT/slides/nginx.conf' \
  --dry-run=client -o yaml | kubectl apply -f -"
run "kubectl apply -f '$STATE/slides.yaml'"
run "kubectl -n $NS rollout status deploy/slides --timeout=300s"

say ""
say "Copying slides/ to the hub and building it there. The first build"
say "downloads the deck's dependencies, so it takes a minute or two."
# node_modules stays on the volume between builds; everything else is replaced.
run "kubectl -n $NS exec deploy/slides -c builder -- sh -c \
  'cd /work/src && find . -mindepth 1 -maxdepth 1 ! -name node_modules -exec rm -rf {} +'"
run "tar -C '$REPO_ROOT/slides' --exclude=./node_modules --exclude=./dist --exclude=./archive -cf - . \
  | kubectl -n $NS exec -i deploy/slides -c builder -- tar -C /work/src -xf -"
run "kubectl -n $NS exec deploy/slides -c builder -- sh -c \
  'cd /work/src && npm ci --no-audit --no-fund && CTF_URL=$CTF_URL npm run build'"
run "kubectl -n $NS exec deploy/slides -c builder -- sh -c \
  'find /work/live -mindepth 1 -delete && cp -r /work/src/dist/. /work/live/ && chmod -R a+rX /work/live'"

wait_for "certificate slides-tls to be issued" 600 \
  "[[ \"\$(kubectl -n $NS get certificate slides-tls -o jsonpath='{.status.conditions[?(@.type==\"Ready\")].status}' 2>/dev/null)\" == 'True' ]]"

say ""
say "Verifying over the public address."
URL="https://$HOST"
wait_for "the deck to answer" 180 "curl -fsS -o /dev/null '$URL/healthz'"
PAGE="$(curl -fsS "$URL/")"
BUNDLE="$(grep -oE 'assets/[A-Za-z0-9_.-]+\.js' <<<"$PAGE" | head -1)"
[[ -n "$BUNDLE" ]] || { fail "the page at $URL/ does not load a script bundle"; exit 1; }
ok "the page loads $BUNDLE"
# Into a file first: `curl | grep -q` fails under pipefail when grep exits early.
curl -fsS -o "$STATE/slides-bundle.js" "$URL/$BUNDLE"
if grep -qF "$CTF_URL" "$STATE/slides-bundle.js"; then
  ok "the join slide points at $CTF_URL"
else
  fail "the built deck does not contain $CTF_URL — the join QR code is wrong"; exit 1
fi

rm -f "$STATE/slides-bundle.js"
echo "$URL" > "$STATE/slides-endpoint"
printf '\n'
ok "The deck is live."
note "slides: $URL"
