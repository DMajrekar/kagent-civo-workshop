#!/usr/bin/env bash
# title: Deploy Grafana to the hub
#
# Grafana is here for two reasons: it is the API that mcp-grafana talks to (so
# it is a hard dependency of the MCP endpoint, not decoration), and it is your
# own window into the dataset when an agent claims something surprising.
source "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib.sh"

STATE="$REPO_ROOT/.state"
export KUBECONFIG="$STATE/hub.kubeconfig"
[[ -f "$KUBECONFIG" ]] || { fail "no hub kubeconfig — run 'make hub-01' first"; exit 1; }
NS="${OBS_NAMESPACE:-observability}"

banner "Hub — step 03: Grafana"

# Password is generated once and kept in .state so re-runs are stable.
PWFILE="$STATE/grafana-admin-password"
if [[ ! -s "$PWFILE" ]]; then
  head -c 18 /dev/urandom | base64 | tr -d '/+=' | head -c 20 > "$PWFILE"
  chmod 600 "$PWFILE"
fi
GRAFANA_PW="$(cat "$PWFILE")"

say "Loki is wired in as a datasource automatically. mcp-grafana will discover"
say "it through the Grafana API rather than being told a Loki URL directly."

cat > "$STATE/grafana-values.yaml" <<YAML
adminUser: admin
adminPassword: "${GRAFANA_PW}"
persistence:
  enabled: false          # nothing here is worth keeping; datasource is declarative
resources:
  requests: { cpu: 50m, memory: 128Mi }
  limits:   { memory: 512Mi }
datasources:
  datasources.yaml:
    apiVersion: 1
    datasources:
      - name: Loki
        type: loki
        uid: workshop-loki
        access: proxy
        url: http://loki.${NS}.svc.cluster.local:3100
        isDefault: true
        jsonData:
          maxLines: 5000
grafana.ini:
  analytics:
    reporting_enabled: false
    check_for_updates: false
  users:
    allow_sign_up: false
    # Viewer alone cannot open Explore, which is the only part of Grafana this
    # workshop actually uses. This grants ad-hoc querying without granting the
    # ability to save anything -- writes still 403.
    viewers_can_edit: true
  # Anonymous read-only access. The point of showing Grafana in the session is
  # that the room can open the same data and try to find what the agent found --
  # which does not work if everyone needs a login first. Viewer role only, and
  # the data is synthetic.
  auth.anonymous:
    enabled: true
    org_name: Main Org.
    org_role: Viewer
  auth:
    disable_login_form: false
  # Land people in Explore rather than an empty dashboard list: there is
  # deliberately no dashboard that answers the question for them.
  dashboards:
    default_home_dashboard_path: ""
YAML

run "helm upgrade --install grafana grafana/grafana \
  --namespace '$NS' \
  --version '${GRAFANA_CHART_VERSION:-8.8.2}' \
  --values '$STATE/grafana-values.yaml' \
  --wait --timeout 8m"

wait_for "Grafana to be ready" 300 \
  "kubectl -n '$NS' get deploy grafana -o jsonpath='{.status.readyReplicas}' | grep -q '^[1-9]'"

# Verify the datasource actually resolves -- a Grafana that is up but cannot
# reach Loki fails later, inside mcp-grafana, where it is much harder to read.
trap cleanup_port_forwards EXIT
port_forward "$NS" svc/grafana 3000:80
wait_for "Grafana to be healthy" 120 "curl -sf -o /dev/null http://127.0.0.1:3000/api/health"

run "curl -sS -u 'admin:$GRAFANA_PW' http://127.0.0.1:3000/api/datasources | jq -r '.[] | \"\\(.name)  type=\\(.type)  uid=\\(.uid)\"'"

say ""
say "Now prove Grafana can actually reach Loki, not just that it has a"
say "datasource object pointing at it."
HEALTH=$(curl -sS -u "admin:$GRAFANA_PW" "http://127.0.0.1:3000/api/datasources/uid/workshop-loki/health" || echo '{}')
echo "$HEALTH" | jq -c . 2>/dev/null || echo "$HEALTH"
if ! echo "$HEALTH" | jq -e '.status == "OK"' >/dev/null 2>&1; then
  fail "Grafana cannot reach Loki — mcp-grafana would fail opaquely later"
  exit 1
fi
ok "Grafana → Loki datasource is healthy"

printf '\n'
ok "Grafana is up."
note "admin password: $PWFILE"
note "browse it with:  kubectl -n $NS port-forward svc/grafana 3000:80"
note "next:  make hub-04   (the applications generating logs)"
