#!/usr/bin/env bash
# title: Deploy Loki to the hub
source "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib.sh"

STATE="$REPO_ROOT/.state"
export KUBECONFIG="$STATE/hub.kubeconfig"
[[ -f "$KUBECONFIG" ]] || { fail "no hub kubeconfig — run 'make hub-01' first"; exit 1; }
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NS="${OBS_NAMESPACE:-observability}"

banner "Hub — step 02: Loki"

say "Single-binary Loki with filesystem storage. The setting that matters is"
say "reject_old_samples=false: the backfill job writes logs dated up to seven"
say "days ago, and Loki would otherwise drop every one of them silently."

run "kubectl create namespace '$NS' --dry-run=client -o yaml | kubectl apply -f -"
run "helm repo add grafana https://grafana.github.io/helm-charts --force-update >/dev/null && helm repo update grafana >/dev/null && echo ok"

run "helm upgrade --install loki grafana/loki \
  --namespace '$NS' \
  --version '${LOKI_CHART_VERSION:-6.24.0}' \
  --values '$HERE/values.yaml' \
  --wait --timeout 10m"

wait_for "Loki to be ready" 600 \
  "kubectl -n '$NS' get pod -l app.kubernetes.io/component=single-binary -o jsonpath='{.items[*].status.containerStatuses[*].ready}' | grep -q true"

run "kubectl -n '$NS' get pods,pvc,svc"

# --------------------------------------------------------------- smoke test
#
# A 204 from the push API only means Loki accepted the write. It says nothing
# about whether anyone can query it back, which for backdated data is a
# genuinely different question -- so assert on the read.

say ""
say "Smoke test: push a line dated two days ago, then read it back."

kubectl -n "$NS" port-forward svc/loki 3100:3100 >/dev/null 2>&1 &
PF_PID=$!
trap 'kill $PF_PID 2>/dev/null || true' EXIT
wait_for "port-forward to Loki" 60 "curl -sf -o /dev/null http://127.0.0.1:3100/ready"

NOW_NS=$(( $(date +%s) * 1000000000 ))
OLD_NS=$(( NOW_NS - 172800000000000 ))
MARKER="backfill-smoke-$(date +%s)"

push_body="{\"streams\":[{\"stream\":{\"service\":\"smoke-test\"},\"values\":[[\"${OLD_NS}\",\"${MARKER}\"]]}]}"
run "curl -sS -o /dev/null -w 'push: HTTP %{http_code}\n' -XPOST http://127.0.0.1:3100/loki/api/v1/push -H 'Content-Type: application/json' --data-raw '$push_body'"

# Count matching entries. Deliberately does NOT swallow errors -- a malformed
# query returning 0 forever is indistinguishable from "not ready yet", and that
# costs you an afternoon.
count_marker() {
  local body
  body=$(curl -sS -G "http://127.0.0.1:3100/loki/api/v1/query_range" \
    --data-urlencode "query={service=\"smoke-test\"}" \
    --data-urlencode "start=$(( OLD_NS - 3600000000000 ))" \
    --data-urlencode "end=${NOW_NS}" \
    --data-urlencode "limit=100") || { echo "CURL_FAILED"; return; }
  LOKI_BODY="$body" MARKER="$MARKER" python3 "$HERE/../../scripts/count-marker.py"
}

say ""
say "Reading it back. Backdated data is not instantly queryable: the ingester"
say "holds the chunk immediately, but the series is not findable for that day"
say "until the TSDB index for it is uploaded. Expect roughly three minutes."

found=0
for attempt in $(seq 1 42); do
  hits=$(count_marker)
  case "$hits" in
    CURL_FAILED|BAD_JSON:*|LOKI_ERROR:*)
      printf '\n'; fail "query failed: $hits"; exit 1 ;;
  esac
  if (( hits > 0 )); then
    found=1; printf '\n'; ok "read the backdated line back after $(( attempt * 10 ))s"; break
  fi
  printf '\r%s  attempt %d/42 — not queryable yet (%ds)%s' "$DIM" "$attempt" "$(( attempt * 10 ))" "$RESET"
  sleep 10
done

if (( ! found )); then
  printf '\n'
  fail "Backdated write was accepted but never became queryable in 7 minutes."
  note "kubectl -n $NS logs loki-0 -c loki | tail -50"
  exit 1
fi

printf '\n'
ok "Loki accepts backdated writes and serves them back. The backfill path works."
note "next:  make hub-03   (Grafana)"
