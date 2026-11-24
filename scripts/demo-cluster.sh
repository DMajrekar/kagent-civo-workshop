#!/usr/bin/env bash
# Create a cluster with Terraform, show that it is empty, and delete it again.
#
#   scripts/demo-cluster.sh
#
# For the slide deck (`make record N=0`): the room plays on a hub that already
# exists, and this is how the deck shows a cluster being created anyway. It is
# a real `terraform apply` of terraform/main.tf, so it makes a real three-node
# cluster, which costs money for the few minutes it exists. The cluster is
# destroyed when this script ends, however it ends.
#
# It has nothing to do with the hub: a different name, its own kubeconfig,
# and Terraform's state kept in .state/demo-cluster/.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_env CIVO_API_KEY
command -v terraform >/dev/null 2>&1 || { fail "terraform is not installed"; exit 1; }

WORK="$REPO_ROOT/.state/demo-cluster"
mkdir -p "$WORK"
cp "$REPO_ROOT/terraform/main.tf" "$WORK/main.tf"
cd "$WORK"

export CIVO_TOKEN="$CIVO_API_KEY"
export TF_VAR_region="$(echo "${CIVO_REGION:-lon1}" | tr '[:upper:]' '[:lower:]')"
export TF_VAR_name="${DEMO_CLUSTER_NAME:-kagent-ctf}"
export TF_IN_AUTOMATION=1
export KUBECONFIG="$WORK/kubeconfig"

destroy() {
  # Off screen, and whatever happened above: nothing is left running.
  terraform destroy -auto-approve -input=false >"$WORK/destroy.log" 2>&1 \
    || printf '\n%sterraform destroy failed -- see %s and delete cluster %s by hand%s\n' \
         "$RED" "$WORK/destroy.log" "$TF_VAR_name" "$RESET" >&2
  rm -f "$KUBECONFIG"
}
trap destroy EXIT

banner "A new cluster, from Terraform"
terraform init -input=false >"$WORK/init.log" 2>&1 || { cat "$WORK/init.log"; exit 1; }

say "One firewall and one cluster. Three nodes."
run "terraform apply -auto-approve"

# Off screen: fetch the kubeconfig and wait for the cluster to finish starting,
# so that the list of pods on the next slide is a settled one.
{
  set -x
  terraform output -raw kubeconfig > "$KUBECONFIG"
  chmod 600 "$KUBECONFIG"
  set +x
  wait_for "the nodes to be ready" 600 \
    "[[ \$(kubectl get nodes --no-headers 2>/dev/null | grep -c ' Ready ') -ge 3 ]]"
  wait_for "the system pods to start" 420 \
    "[[ \$(kubectl get pods -A --no-headers 2>/dev/null | wc -l) -ge 5 && \$(kubectl get pods -A --no-headers 2>/dev/null | grep -c 'Pending\|ContainerCreating\|Init:') -eq 0 ]]" \
    || { kubectl get pods -A; kubectl get nodes; exit 1; }
} >"$WORK/wait.log" 2>&1

say ""
say "Nothing on it yet but Kubernetes itself."
run "kubectl get pods -A"
