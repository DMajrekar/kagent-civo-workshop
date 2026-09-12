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

# Collect the cluster's volumes BEFORE deleting it. Civo does not delete the
# volumes a cluster's PVCs created -- they are left "available" and keep
# billing -- and once the cluster is gone the association is gone with it, so
# you can no longer tell which volumes were yours.
say "Finding the volumes this cluster created, before deleting it."
VOLS=$(civo_cluster_volumes "$CID" "$REGION")
if [[ -n "$VOLS" ]]; then
  note "$(echo "$VOLS" | wc -l) volume(s) to clean up afterwards"
else
  note "no volumes found attached to this cluster"
fi

# The dashboard forward points at a cluster that is about to stop existing.
bash "$REPO_ROOT/scripts/ui.sh" stop >/dev/null 2>&1 || true

run "civo kubernetes remove '$CID' --region '$REGION' --yes"

if [[ -n "$VOLS" ]]; then
  say ""
  say "Now the volumes. Civo leaves these behind when a cluster is deleted, and"
  say "they keep billing -- this is the step people miss."
  for v in $VOLS; do
    run "civo volume remove '$v' --region '$REGION' --yes || true"
  done
fi

rm -f "$STATE/workshop.kubeconfig" "$STATE/cluster.env"

printf '\n'
ok "Cluster and its volumes deleted."

# Give the API a moment: volumes deleted a second ago can still list as
# available, and warning about the ones we just removed is worse than useless.
sleep 5
ORPHANS=$(civo_orphan_volumes "$REGION")
if [[ -n "$ORPHANS" ]]; then
  warn "There are still unattached volumes in $REGION that are billing:"
  echo "$ORPHANS" | while IFS=$'\t' read -r id name size; do
    note "  $id  $name  $size"
  done
  note "these may be from other work — remove with: civo volume remove <id> --region $REGION"
else
  ok "no unattached volumes left in $REGION"
fi
note "check nothing is left behind:  civo kubernetes ls --region $REGION"
