#!/usr/bin/env bash
# title: A report in your inbox every morning
source "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib.sh"

STATE="$REPO_ROOT/.state"
export KUBECONFIG="$STATE/workshop.kubeconfig"
[[ -f "$KUBECONFIG" ]] || { fail "no kubeconfig — run 'make step-02' first"; exit 1; }
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE="${REPORT_IMAGE:-python:3.12-alpine}"
SCHEDULE="${REPORT_SCHEDULE:-0 7 * * *}"
HOOK="${REPORT_WEBHOOK_URL:-}"

banner "Step 05 — a report every morning"

if [[ -z "$HOOK" ]]; then
  SINK="$(cat "$STATE/sink-endpoint" 2>/dev/null || true)"
  warn "REPORT_WEBHOOK_URL is not set in your .env"
  [[ -n "$SINK" ]] && note "open $SINK , get your code, and paste the URL into .env"
  note "carrying on without it — the report will print to the job's logs instead"
fi

say "An agent you have to remember to ask is an agent you stop using. This is"
say "the same agent, on a schedule, writing to somewhere you will actually see."

run_quiet "kubectl -n kagent create configmap daily-report \
  --from-file=report.py='$HERE/report.py' \
  --dry-run=client -o yaml | kubectl apply -f -"

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
      # The agent thinks for 30-60 seconds and may call a dozen tools. Give the
      # job room; a report that gets killed halfway is worse than none.
      activeDeadlineSeconds: 900
      template:
        spec:
          restartPolicy: Never
          containers:
            - name: report
              image: ${IMAGE}
              command: ["python3", "/app/report.py"]
              env:
                - { name: AGENT_URL, value: "http://my-agent.kagent.svc.cluster.local:8080" }
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
run "kubectl apply -f '$STATE/report-cronjob.yaml'"
run "kubectl -n kagent get cronjob daily-report"

say ""
say "Tomorrow at $(echo "$SCHEDULE" | awk '{print $2":"$1}') that runs on its own. Waiting until then would"
say "make for a poor demo, so trigger one now."

run "kubectl -n kagent delete job report-now --ignore-not-found"
run "kubectl -n kagent create job report-now --from=cronjob/daily-report"

wait_for "the report job to start" 180 \
  "kubectl -n kagent get pod -l job-name=report-now -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -Eq 'Running|Succeeded|Failed'"

say ""
say "This takes a minute. The agent is querying seven days of logs, writing"
say "LogQL as it goes, and composing the answer."
run "kubectl -n kagent logs -f job/report-now"

if kubectl -n kagent wait --for=condition=complete job/report-now --timeout=900s >/dev/null 2>&1; then
  ok "report generated"
else
  fail "the report job did not complete"
  run_quiet "kubectl -n kagent describe job report-now"
  exit 1
fi

printf '\n'
ok "You have an agent that reports for duty every morning."
if [[ -n "$HOOK" ]]; then
  note "it just posted to: $HOOK"
  note "open your inbox page and it will be there"
else
  note "set REPORT_WEBHOOK_URL in .env and re-run to have it posted to your page"
fi
note "change the schedule: REPORT_SCHEDULE='0 9 * * 1' make step-05   (Mondays)"
note "change the question: edit PROMPT in $HERE/report.py"
note "next:  make step-06"
