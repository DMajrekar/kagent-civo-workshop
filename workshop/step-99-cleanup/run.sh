#!/usr/bin/env bash
# title: Delete your cluster
#
# Not part of the workshop -- attendees keep their clusters. This is here for
# when they have finished with it, and for rehearsals.
source "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib.sh"

require_env CIVO_API_KEY
NAME="${CLUSTER_NAME:-kagent-workshop}"
REGION="$(echo "${CIVO_REGION:-lon1}" | tr '[:upper:]' '[:lower:]')"
STATE="$REPO_ROOT/.state"

banner "Cleanup — delete your cluster"

civo apikey add workshop "$CIVO_API_KEY" >/dev/null 2>&1 || true
civo apikey current workshop >/dev/null 2>&1 || true

CID="$(civo_cluster_id "$NAME" "$REGION")"
if [[ -z "$CID" ]]; then
  ok "no cluster named exactly '$NAME' in $REGION — nothing to delete"
  exit 0
fi

warn "This permanently deletes the cluster '$NAME' ($CID) and everything on it."
say ""
say "Your cluster bills to your own Civo account until you do this. If you want"
say "to keep the agent but spend less, scale it down instead:"
note "civo kubernetes scale $NAME --nodes=1 --region $REGION"
printf '\n'

if [[ -z "${DEMO_AUTO-}" && -t 0 ]]; then
  printf '%s%sType the cluster name to confirm deletion: %s' "$BOLD" "$YELLOW" "$RESET"
  read -r CONFIRM < /dev/tty || true
  if [[ "$CONFIRM" != "$NAME" ]]; then
    ok "not deleting anything"
    exit 0
  fi
fi

run "civo kubernetes remove '$CID' --region '$REGION' --yes"
rm -f "$STATE/workshop.kubeconfig" "$STATE/cluster.env"
printf '\n'
ok "Cluster deleted. Any Civo LoadBalancers and volumes it created go with it."
note "check nothing is left behind:  civo kubernetes ls --region $REGION"
