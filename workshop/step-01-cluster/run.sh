#!/usr/bin/env bash
# title: Create your Kubernetes cluster
#
# Kicked off asynchronously on purpose. Civo takes a couple of minutes, and
# twenty-five people watching a spinner is twenty-five people not listening.
# Step 02 blocks on readiness, so start this and carry on.
source "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib.sh"

require_env CIVO_API_KEY
NAME="${CLUSTER_NAME:-kagent-workshop}"
REGION="$(echo "${CIVO_REGION:-lon1}" | tr '[:upper:]' '[:lower:]')"
SIZE="${CIVO_NODE_SIZE:-g4s.kube.medium}"
NODES="${CIVO_NODE_COUNT:-2}"
K8S="${CIVO_K8S_VERSION:-1.35.0-k3s1}"
STATE="$REPO_ROOT/.state"; mkdir -p "$STATE"
KCFG="$STATE/workshop.kubeconfig"

banner "Step 01 — your cluster"

say "You are about to build an AI agent that lives inside Kubernetes. First it"
say "needs somewhere to live. This creates a two-node cluster on Civo in your"
say "own account -- you keep it at the end of the session."
printf '\n'
note "cluster: $NAME   region: $REGION   nodes: ${NODES}x $SIZE"

civo apikey add workshop "$CIVO_API_KEY" >/dev/null 2>&1 || true
civo apikey current workshop >/dev/null 2>&1 || true

# Exact match only -- see civo_cluster_id in scripts/lib.sh for why.
if civo_cluster_exists "$NAME" "$REGION"; then
  ok "cluster '$NAME' already exists — reusing it"
else
  run "civo kubernetes create '$NAME' \
    --region '$REGION' --size '$SIZE' --nodes '$NODES' --version '$K8S' \
    --applications '-traefik2-nodeport,metrics-server' \
    --wait=false --yes"
fi

printf '\n'
ok "Cluster creation is under way."
say ""
say "This takes two or three minutes. You do NOT need to wait -- step 02 waits"
say "for you. Go and listen to the bit about what kagent actually is."
printf '\n'
note "check on it any time with:  civo kubernetes show $NAME --region $REGION"
note "next:  make step-02"

# Save what step 02 needs, so it does not have to re-read .env.
cat > "$STATE/cluster.env" <<VARS
CLUSTER_NAME=$NAME
CIVO_REGION=$REGION
KUBECONFIG_PATH=$KCFG
VARS
