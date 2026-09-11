#!/usr/bin/env bash
# title: Backfill 7 days of history and validate it
#
# Backfill is the guarantee that the dataset tells its story on the day,
# regardless of how long the hub has actually been running. It is also how you
# re-seed on the morning of the event so "the last 24 hours" is fresh.
#
#   make hub-05             backfill, then validate
#   WIPE=1 make hub-05      wipe Loki first (clean re-seed)
#   VALIDATE_ONLY=1 make hub-05
source "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib.sh"

STATE="$REPO_ROOT/.state"
export KUBECONFIG="$STATE/hub.kubeconfig"
[[ -f "$KUBECONFIG" ]] || { fail "no hub kubeconfig — run 'make hub-01' first"; exit 1; }
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NS="${OBS_NAMESPACE:-observability}"
IMAGE="${GENERATOR_IMAGE:-python:3.12-alpine}"
DAYS="${BACKFILL_DAYS:-7}"

banner "Hub — step 05: backfill and validate"

if [[ -n "${WIPE-}" ]]; then
  warn "WIPE=1 — deleting all existing log data"
  run "kubectl -n '$NS' scale statefulset loki --replicas=0"
  wait_for "Loki to stop" 120 "! kubectl -n '$NS' get pod loki-0 >/dev/null 2>&1"
  run "kubectl -n '$NS' delete pvc storage-loki-0 --ignore-not-found"
  run "kubectl -n '$NS' scale statefulset loki --replicas=1"
  wait_for "Loki to come back" 300 \
    "[[ \"\$(kubectl -n '$NS' get pod loki-0 -o jsonpath='{.status.containerStatuses[*].ready}' 2>/dev/null)\" == 'true true' ]]"
fi

if [[ -z "${VALIDATE_ONLY-}" ]]; then
  # Stop live generation first. Both write to the same streams, and Loki only
  # accepts out-of-order entries within a window derived from max_chunk_age --
  # a live writer stamping "now" makes every backdated entry too far behind,
  # and the entire backfill is rejected with a bare HTTP 400.
  say "Pausing live generation so the backfill is not racing it."
  if kubectl -n "$NS" get deploy log-generator >/dev/null 2>&1; then
    run "kubectl -n '$NS' scale deploy/log-generator --replicas=0"
    wait_for "live generator to stop" 120 \
      "[[ \$(kubectl -n '$NS' get pod -l app=log-generator --no-headers 2>/dev/null | wc -l) -eq 0 ]]"
  else
    note "no live generator deployed yet — nothing to pause"
  fi

  # Refresh the ConfigMap so the job runs what is in the repo right now.
  run "kubectl -n '$NS' create configmap log-generator \
    --from-file=generator.py='$REPO_ROOT/hub/step-04-workloads/generator.py' \
    --from-file=validate.py='$HERE/validate.py' \
    --dry-run=client -o yaml | kubectl apply -f -"

  run "kubectl -n '$NS' delete job backfill --ignore-not-found"

  cat > "$STATE/backfill-job.yaml" <<YAML
apiVersion: batch/v1
kind: Job
metadata:
  name: backfill
  namespace: ${NS}
spec:
  backoffLimit: 1
  ttlSecondsAfterFinished: 3600
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
          volumeMounts:
            - { name: app, mountPath: /app }
          resources:
            requests: { cpu: 200m, memory: 128Mi }
            limits:   { memory: 512Mi }
      volumes:
        - name: app
          configMap: { name: log-generator }
YAML

  say "Writing ${DAYS} days of history. This runs in-cluster rather than from"
  say "your laptop -- a dropped port-forward halfway through a backfill leaves"
  say "a dataset with a hole in it that nothing will tell you about."
  run "kubectl apply -f '$STATE/backfill-job.yaml'"

  wait_for "backfill job to start" 180 \
    "kubectl -n '$NS' get pod -l job-name=backfill -o jsonpath='{.items[0].status.phase}' | grep -Eq 'Running|Succeeded'"
  run "kubectl -n '$NS' logs -f job/backfill --tail=20"

  if ! kubectl -n "$NS" wait --for=condition=complete job/backfill --timeout=1800s >/dev/null 2>&1; then
    fail "backfill job did not complete"
    run_quiet "kubectl -n '$NS' describe job backfill"
    exit 1
  fi
  ok "backfill job completed"

  say ""
  say "Resuming live generation."
  run "kubectl -n '$NS' scale deploy/log-generator --replicas=1"
  run "kubectl -n '$NS' rollout status deploy/log-generator --timeout=180s"
fi

# ---------------------------------------------------------------- validation
say ""
say "Backdated data takes a few minutes to become queryable -- the ingester has"
say "it immediately, but the series is not findable for those days until the"
say "TSDB index is uploaded. Waiting before we validate."

wait_for "index to settle" 420 "sleep 180; true"

run "kubectl -n '$NS' delete pod dataset-validate --ignore-not-found"
say ""
say "Now assert all six planted incidents are actually discoverable, using the"
say "same kind of aggregate queries an agent would have to write."
set +e
kubectl -n "$NS" run dataset-validate \
  --image="$IMAGE" --restart=Never --attach --rm --quiet \
  --overrides="$(cat <<JSON
{"spec":{"containers":[{"name":"dataset-validate","image":"${IMAGE}",
 "command":["python3","/app/validate.py"],
 "env":[{"name":"LOKI_URL","value":"http://loki.${NS}.svc.cluster.local:3100"},
        {"name":"PYTHONUNBUFFERED","value":"1"}],
 "volumeMounts":[{"name":"app","mountPath":"/app"}]}],
 "volumes":[{"name":"app","configMap":{"name":"log-generator"}}]}}
JSON
)"
VRC=$?
set -e

printf '\n'
if (( VRC != 0 )); then
  fail "The dataset does not tell its story. Step-04 would fall flat."
  note "Re-run with WIPE=1 make hub-05 for a clean seed, or check the"
  note "incident definitions in hub/step-04-workloads/generator.py"
  exit 1
fi
ok "Seven days of history are in place and every incident is discoverable."
note "next:  make hub-06   (the MCP endpoint)"
