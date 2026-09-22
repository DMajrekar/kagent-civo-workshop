#!/usr/bin/env bash
# title: Put it on a schedule
#
# Flow: run the report once and look at what it wrote, then show what running
# it every morning would take. The CronJob is displayed, not applied -- nobody
# needs a scheduled job firing while we are still talking about it.
source "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib.sh"

STATE="$REPO_ROOT/.state"
export KUBECONFIG="$STATE/workshop.kubeconfig"
[[ -f "$KUBECONFIG" ]] || { fail "no kubeconfig — run 'make step-02' first"; exit 1; }
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE="${REPORT_IMAGE:-python:3.12-alpine}"
SCHEDULE="${REPORT_SCHEDULE:-0 7 * * *}"
HOOK="${REPORT_WEBHOOK_URL:-}"

banner "Step 05 — put it on a schedule"

if [[ -z "$HOOK" ]]; then
  SINK="$(cat "$STATE/sink-endpoint" 2>/dev/null || true)"
  warn "REPORT_WEBHOOK_URL is not set in your .env"
  [[ -n "$SINK" ]] && note "grab your code at $SINK and paste the URL into .env"
  note "carrying on — the report will print here instead of posting"
fi

say "An agent you have to remember to ask is an agent you stop using."
say ""
say "So: ask it once, properly, and look at what comes back."

run_quiet "kubectl -n kagent create configmap daily-report \
  --from-file=report.py='$HERE/report.py' \
  --dry-run=client -o yaml | kubectl apply -f -"

# ----------------------------------------------------------- run it once
cat > "$STATE/report-job.yaml" <<YAML
apiVersion: batch/v1
kind: Job
metadata:
  name: report-now
  namespace: kagent
spec:
  backoffLimit: 1
  ttlSecondsAfterFinished: 3600
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: report
          image: ${IMAGE}
          command: ["python3", "/app/report.py"]
          env:
            - { name: AGENT_URL, value: "http://log-detective.kagent.svc.cluster.local:8080" }
            - { name: REPORT_WEBHOOK_URL, value: "${HOOK}" }
            - { name: PYTHONUNBUFFERED, value: "1" }
          volumeMounts: [{ name: app, mountPath: /app }]
          resources:
            requests: { cpu: 20m, memory: 48Mi }
            limits:   { memory: 192Mi }
      volumes:
        - name: app
          configMap: { name: daily-report }
YAML

run "kubectl -n kagent delete job report-now --ignore-not-found"
run "kubectl apply -f '$STATE/report-job.yaml'"

wait_for "the report job to start" 180 \
  "kubectl -n kagent get pod -l job-name=report-now -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -Eq 'Running|Succeeded|Failed'"

say ""
say "It is querying seven days of logs and writing the LogQL as it goes."
say "Give it a minute."
run "kubectl -n kagent logs -f job/report-now"

if ! kubectl -n kagent wait --for=condition=complete job/report-now --timeout=900s >/dev/null 2>&1; then
  fail "the report job did not complete"
  run_quiet "kubectl -n kagent describe job report-now"
  exit 1
fi
printf '\n'
ok "That is the report."
[[ -n "$HOOK" ]] && note "it also posted to your page: $HOOK"

pause "talk about what it found"

# -------------------------------------------------- show the schedule, don't set it
say ""
say "Running that every morning is the same pod with a schedule around it."
say "Here is the whole thing:"

cat > "$STATE/report-cronjob.yaml" <<YAML
apiVersion: batch/v1
kind: CronJob
metadata:
  name: daily-report
  namespace: kagent
spec:
  schedule: "${SCHEDULE}"
  concurrencyPolicy: Forbid
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 3
  jobTemplate:
    spec:
      backoffLimit: 1
      # The agent thinks for 30-60s and may call a dozen tools. A report killed
      # halfway is worse than no report.
      activeDeadlineSeconds: 900
      template:
        spec:
          restartPolicy: Never
          containers:
            - name: report
              image: ${IMAGE}
              command: ["python3", "/app/report.py"]
              env:
                - { name: AGENT_URL, value: "http://log-detective.kagent.svc.cluster.local:8080" }
                - { name: REPORT_WEBHOOK_URL, value: "${HOOK}" }
                - { name: PYTHONUNBUFFERED, value: "1" }
              volumeMounts: [{ name: app, mountPath: /app }]
              resources:
                requests: { cpu: 20m, memory: 48Mi }
                limits:   { memory: 192Mi }
          volumes:
            - name: app
              configMap: { name: daily-report }
YAML

run "cat '$STATE/report-cronjob.yaml'"
