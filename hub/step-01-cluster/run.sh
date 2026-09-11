#!/usr/bin/env bash
# title: Create the hub cluster
#
# The hub is the shared observability cluster the instructor runs. It holds
# Loki with seven days of seeded logs, the applications generating them, the
# MCP endpoint attendees point their agents at, and the webhook wall.
#
# Idempotent: if the cluster already exists this just refetches the kubeconfig.
source "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib.sh"

require_env CIVO_API_KEY
HUB_NAME="${HUB_CLUSTER_NAME:-kagent-workshop-hub}"
HUB_REGION="$(echo "${CIVO_REGION:-lon1}" | tr '[:upper:]' '[:lower:]')"
HUB_SIZE="${HUB_NODE_SIZE:-g4s.kube.medium}"
HUB_NODES="${HUB_NODE_COUNT:-2}"
HUB_K8S="${HUB_K8S_VERSION:-1.35.0-k3s1}"
STATE="$REPO_ROOT/.state"; mkdir -p "$STATE"
export KUBECONFIG="$STATE/hub.kubeconfig"

banner "Hub — step 01: the cluster"

say "Everything the attendees query lives here. One cluster, running from now"
say "until a month after the event, holding the logs their agents will read."
printf '\n'
note "cluster: $HUB_NAME   region: $HUB_REGION   nodes: ${HUB_NODES}x $HUB_SIZE"

civo apikey add workshop "$CIVO_API_KEY" >/dev/null 2>&1 || true
civo apikey current workshop >/dev/null 2>&1 || true

if civo_cluster_exists "$HUB_NAME" "$HUB_REGION"; then
  ok "cluster $HUB_NAME already exists — reusing it"
else
  pause "create the cluster"
  run "civo kubernetes create '$HUB_NAME' \
    --region '$HUB_REGION' \
    --size '$HUB_SIZE' \
    --nodes '$HUB_NODES' \
    --version '$HUB_K8S' \
    --applications '-traefik2-nodeport,metrics-server' \
    --wait=false --yes"
fi

# Poll rather than using --wait, so re-running the step while it builds is safe.
HUB_ID="$(civo_cluster_id "$HUB_NAME" "$HUB_REGION")"
[[ -n "$HUB_ID" ]] || { fail "cluster $HUB_NAME not found after create"; exit 1; }
wait_for "cluster to become ACTIVE" 900 \
  "[[ \"\$(civo_cluster_field '$HUB_ID' '$HUB_REGION' Status)\" == 'ACTIVE' ]]"

# Write via stdout rather than --save: --save prompts for confirmation when
# KUBECONFIG already points at the target path, which deadlocks a non-tty run.
run "( unset KUBECONFIG; civo kubernetes config '$HUB_ID' --region '$HUB_REGION' ) > '$KUBECONFIG'"
chmod 600 "$KUBECONFIG"
kubectl config current-context >/dev/null 2>&1 || { fail "kubeconfig did not parse"; exit 1; }

wait_for "all nodes Ready" 600 \
  "[[ \$(kubectl get nodes --no-headers 2>/dev/null | grep -c ' Ready ') -ge $HUB_NODES ]]"

run "kubectl get nodes -o wide"

printf '\n'
ok "Hub cluster is up."
note "kubeconfig: $KUBECONFIG"
note "use it with:  export KUBECONFIG=$KUBECONFIG"
note "next:  make hub-02   (Loki)"
