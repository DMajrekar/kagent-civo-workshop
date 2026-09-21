#!/usr/bin/env bash
# title: Install kagent and point it at relax.ai
source "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib.sh"

require_env CIVO_API_KEY RELAX_API_KEY
NAME="${CLUSTER_NAME:-kagent-workshop}"
REGION="$(echo "${CIVO_REGION:-lon1}" | tr '[:upper:]' '[:lower:]')"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE="$REPO_ROOT/.state"; mkdir -p "$STATE"
export KUBECONFIG="$STATE/workshop.kubeconfig"
# Pinned, not floating. A chart release landing between a rehearsal and the
# session would hand attendees a version nobody has run. Override with
# KAGENT_VERSION when you deliberately want to move.
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
  --namespace kagent --create-namespace --wait --timeout 5m \
  --version '${KAGENT_VERSION:-0.10.1}'"

say ""
say "Your relax.ai key goes into a Secret. kagent reads it from there, so you"
say "can swap the key later without touching any other resource."
# Deliberately not shown via run/run_quiet: both echo the command, and this one
# carries a live API key. On a screenshare that puts it on the projector.
printf '\n%s%s$ kubectl -n kagent create secret generic kagent-relax --from-literal=RELAX_API_KEY=****%s\n' \
  "$BOLD" "$GREEN" "$RESET"
if kubectl -n kagent create secret generic kagent-relax \
     --from-literal=RELAX_API_KEY="$RELAX_API_KEY" \
     --dry-run=client -o yaml | kubectl apply -f - >/dev/null; then
  ok "secret created"
else
  fail "could not create the relax.ai secret"; exit 1
fi

# values.yaml is the source of truth. Only override it when .env actually asks
# for something different -- passing --set for values the file already declares
# means two places to change and one of them silently losing.
FILE_MODEL=$(python3 -c "import yaml,sys;print(yaml.safe_load(open(sys.argv[1]))['providers']['openAI']['model'])" "$HERE/values.yaml")
FILE_URL=$(python3 -c "import yaml,sys;print(yaml.safe_load(open(sys.argv[1]))['providers']['openAI']['config']['baseUrl'])" "$HERE/values.yaml")
OVERRIDE=""
[[ "$MODEL"    != "$FILE_MODEL" ]] && { OVERRIDE+=" --set providers.openAI.model=$MODEL"; note "overriding model from .env: $FILE_MODEL -> $MODEL"; }
[[ "$BASE_URL" != "$FILE_URL"   ]] && { OVERRIDE+=" --set providers.openAI.config.baseUrl=$BASE_URL"; note "overriding baseUrl from .env: $FILE_URL -> $BASE_URL"; }

run "helm upgrade --install kagent oci://ghcr.io/kagent-dev/kagent/helm/kagent \
  --namespace kagent --create-namespace --wait --timeout 10m \
  --values '$HERE/values.yaml'$OVERRIDE \
  --version '${KAGENT_VERSION:-0.10.1}'"

wait_for "the kagent controller to be ready" 600 \
  "kubectl -n kagent get deploy kagent-controller -o jsonpath='{.status.readyReplicas}' 2>/dev/null | grep -q '^[1-9]'"
run "kubectl -n kagent get pods"

# ------------------------------------------------------------ ModelConfig
say ""
say "That values file is worth a look — the whole relax.ai integration is one"
say "block in it. relax.ai speaks the OpenAI API, so kagent reaches it as an"
say "OpenAI provider with a different address."
run "sed -n '/^providers:/,/^$/p' '$HERE/values.yaml'"

say ""
say "Which the chart turned into this, before any agent started:"
run "kubectl -n kagent get modelconfig default-model-config -o yaml | grep -A8 '^spec:'"

# The agents read this at startup. If the baseUrl were missing they would come
# up pointing at api.openai.com with a relax.ai key and 401 on the first
# question -- so assert it rather than trusting the chart across versions.
ACTUAL=$(kubectl -n kagent get modelconfig default-model-config \
  -o jsonpath='{.spec.openAI.baseUrl}' 2>/dev/null || true)
if [[ "$ACTUAL" != "$BASE_URL" ]]; then
  fail "ModelConfig baseUrl is '${ACTUAL:-empty}', expected '$BASE_URL'"
  note "Without it the agents call api.openai.com with a relax.ai key and 401."
  note "Check providers.openAI.config.baseUrl in $HERE/values.yaml"
  exit 1
fi
ok "agents are pointed at relax.ai from the moment they start"

printf '\n'
ok "kagent is running and knows how to reach relax.ai."
note "kubeconfig: $KUBECONFIG"
note "next:  make step-03   (your first agent)"
