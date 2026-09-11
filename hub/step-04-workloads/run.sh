#!/usr/bin/env bash
# title: Deploy the log-generating applications
#
# The fleet is a single generator process simulating eight services (see
# docs/INCIDENTS.md). It pushes straight to Loki's API rather than writing to
# stdout for a collector to scrape: we need exact control over labels for the
# planted incidents, and it means the backfill job and the live generator share
# one code path instead of two that can drift.
source "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib.sh"

STATE="$REPO_ROOT/.state"
export KUBECONFIG="$STATE/hub.kubeconfig"
[[ -f "$KUBECONFIG" ]] || { fail "no hub kubeconfig — run 'make hub-01' first"; exit 1; }
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NS="${OBS_NAMESPACE:-observability}"
IMAGE="${GENERATOR_IMAGE:-python:3.12-alpine}"

banner "Hub — step 04: the applications"

say "Eight services, each misbehaving in a specific and discoverable way."
say "This deployment generates live traffic from now on; step 05 backfills the"
say "seven days of history behind it."

# One ConfigMap holds both the generator and the validator, so the cluster
# always runs exactly what is in the repo.
run "kubectl -n '$NS' create configmap log-generator \
  --from-file=generator.py='$HERE/generator.py' \
  --from-file=validate.py='$REPO_ROOT/hub/step-05-backfill/validate.py' \
  --dry-run=client -o yaml | kubectl apply -f -"

cat > "$STATE/generator-deploy.yaml" <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: log-generator
  namespace: ${NS}
  labels: { app: log-generator }
spec:
  replicas: 1
  selector:
    matchLabels: { app: log-generator }
  template:
    metadata:
      labels: { app: log-generator }
      annotations:
        # Roll the pod whenever the script changes, so 'make hub-04' after an
        # edit actually runs the new code instead of silently keeping the old.
        generator/checksum: "$(sha256sum "$HERE/generator.py" | cut -c1-16)"
    spec:
      containers:
        - name: generator
          image: ${IMAGE}
          command: ["python3", "/app/generator.py", "--live"]
          env:
            - name: LOKI_URL
              value: http://loki.${NS}.svc.cluster.local:3100
            - name: PYTHONUNBUFFERED
              value: "1"
          volumeMounts:
            - { name: app, mountPath: /app }
          resources:
            requests: { cpu: 50m, memory: 64Mi }
            limits:   { memory: 256Mi }
      volumes:
        - name: app
          configMap: { name: log-generator }
YAML

run "kubectl apply -f '$STATE/generator-deploy.yaml'"
run "kubectl -n '$NS' rollout status deploy/log-generator --timeout=180s"

say ""
say "Confirm lines are actually arriving, rather than trusting a Running pod."
wait_for "live logs to appear in Loki" 180 \
  "kubectl -n '$NS' exec loki-0 -c loki -- wget -qO- 'http://localhost:3100/loki/api/v1/query?query=sum(count_over_time(%7Benv%3D%22production%22%7D%5B2m%5D))' | grep -q '\"value\"'"

run "kubectl -n '$NS' logs deploy/log-generator --tail=5"

printf '\n'
ok "The fleet is running and writing to Loki."
note "next:  make hub-05   (backfill seven days of history)"
