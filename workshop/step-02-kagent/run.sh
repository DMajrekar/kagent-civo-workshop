#!/usr/bin/env bash
# title: Install kagent and point it at relax.ai
source "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib.sh"

require_env CIVO_API_KEY RELAX_API_KEY
NAME="${CLUSTER_NAME:-kagent-workshop}"
REGION="$(echo "${CIVO_REGION:-lon1}" | tr '[:upper:]' '[:lower:]')"
STATE="$REPO_ROOT/.state"; mkdir -p "$STATE"
export KUBECONFIG="$STATE/workshop.kubeconfig"
MODEL="${RELAX_MODEL:-DeepSeek-V4-Pro}"
BASE_URL="${RELAX_BASE_URL:-https://api.relax.ai/v1}"

banner "Step 02 — kagent"

say "kagent runs AI agents as Kubernetes resources. An Agent is a CRD, its"
say "model is a CRD, its tools are CRDs. Nothing here is a hosted service --"
say "it is all running in the cluster you just made."

civo apikey add workshop "$CIVO_API_KEY" >/dev/null 2>&1 || true
civo apikey current workshop >/dev/null 2>&1 || true

CID="$(civo_cluster_id "$NAME" "$REGION")"
[[ -n "$CID" ]] || { fail "no cluster named exactly '$NAME' in $REGION — run 'make step-01' first"; exit 1; }

say ""
say "Waiting for your cluster. If you started step 01 a few minutes ago this"
say "will be quick."
wait_for "cluster '$NAME' to be ACTIVE" 900 \
  "[[ \"\$(civo_cluster_field '$CID' '$REGION' Status)\" == 'ACTIVE' ]]"

run "( unset KUBECONFIG; civo kubernetes config '$CID' --region '$REGION' ) > '$KUBECONFIG'"
chmod 600 "$KUBECONFIG"
kubectl config current-context >/dev/null 2>&1 || { fail "kubeconfig did not parse"; exit 1; }

wait_for "nodes to be Ready" 600 \
  "[[ \$(kubectl get nodes --no-headers 2>/dev/null | grep -c ' Ready ') -ge 1 ]]"
run "kubectl get nodes"

# --------------------------------------------------------------- install
say ""
say "The CRDs go on first, as a separate chart -- kagent's own chart expects"
say "them to already exist."
run "helm upgrade --install kagent-crds oci://ghcr.io/kagent-dev/kagent/helm/kagent-crds \
  --namespace kagent --create-namespace --wait --timeout 5m ${KAGENT_VERSION:+--version $KAGENT_VERSION}"

say ""
say "Your relax.ai key goes into a Secret. kagent reads it from there, so you"
say "can swap the key later without touching any other resource."
run_quiet "kubectl -n kagent create secret generic kagent-relax \
  --from-literal=RELAX_API_KEY='$RELAX_API_KEY' \
  --dry-run=client -o yaml | kubectl apply -f -"

# The chart ships ten built-in agents (Istio, Cilium, Argo, kgateway...). Each
# is its own Deployment, which is a lot of pods and a lot of noise on a
# two-node cluster for a sixty-minute session. Keep k8s-agent -- that is the
# hello-world -- and switch the rest off. They are one --set away if wanted.
UNUSED_AGENTS=(kgateway-agent istio-agent promql-agent observability-agent
               argo-rollouts-agent helm-agent cilium-policy-agent
               cilium-manager-agent cilium-debug-agent)
DISABLE=""
for a in "${UNUSED_AGENTS[@]}"; do DISABLE+=" --set ${a}.enabled=false"; done

run "helm upgrade --install kagent oci://ghcr.io/kagent-dev/kagent/helm/kagent \
  --namespace kagent --create-namespace --wait --timeout 10m \
  --set providers.openAI.model='$MODEL' \
  --set providers.openAI.apiKeySecretRef=kagent-relax \
  --set providers.openAI.apiKeySecretKey=RELAX_API_KEY \
  $DISABLE ${KAGENT_VERSION:+--version $KAGENT_VERSION}"

wait_for "the kagent controller to be ready" 600 \
  "kubectl -n kagent get deploy kagent-controller -o jsonpath='{.status.readyReplicas}' 2>/dev/null | grep -q '^[1-9]'"
run "kubectl -n kagent get pods"

# ------------------------------------------------------------ ModelConfig
say ""
say "relax.ai speaks the OpenAI API, so kagent reaches it with provider: OpenAI"
say "and a different baseUrl. That is the entire integration."
say ""
say "The chart does not template baseUrl, so patch it onto the ModelConfig the"
say "chart generated. Everything else -- model name, which Secret holds the key"
say "-- we already passed as Helm values."

run "kubectl -n kagent patch modelconfig default-model-config --type=merge \
  -p '{\"spec\":{\"openAI\":{\"baseUrl\":\"${BASE_URL}\"}}}'"

say ""
say "This is the whole model wiring, in one resource:"
run "kubectl -n kagent get modelconfig default-model-config -o yaml | grep -A8 '^spec:'"

say ""
say "Agents read their model config when they start, and Helm started the"
say "built-in one before that patch existed -- so right now it is still trying"
say "to reach api.openai.com with a relax.ai key. Restart it."
for d in $(kubectl -n kagent get deploy -o name 2>/dev/null | grep -E 'agent$' | grep -v 'kagent-'); do
  run "kubectl -n kagent rollout restart $d"
done
run "kubectl -n kagent rollout status deploy/k8s-agent --timeout=300s"

printf '\n'
ok "kagent is running and knows how to reach relax.ai."
note "kubeconfig: $KUBECONFIG"
note "next:  make step-03   (your first agent)"
