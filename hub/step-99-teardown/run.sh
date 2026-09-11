#!/usr/bin/env bash
# title: Tear down the hub
#
# Run this on 2026-10-22, a month after the event, once attendees have had
# their notice. Everything in .state goes with it.
source "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib.sh"

require_env CIVO_API_KEY
HUB_NAME="${HUB_CLUSTER_NAME:-kagent-workshop-hub}"
REGION="$(echo "${CIVO_REGION:-lon1}" | tr '[:upper:]' '[:lower:]')"
STATE="$REPO_ROOT/.state"

banner "Hub — teardown"

civo apikey add workshop "$CIVO_API_KEY" >/dev/null 2>&1 || true
civo apikey current workshop >/dev/null 2>&1 || true

CID="$(civo_cluster_id "$HUB_NAME" "$REGION")"
if [[ -z "$CID" ]]; then
  ok "no cluster named exactly '$HUB_NAME' in $REGION — nothing to delete"
  exit 0
fi

warn "This deletes the shared hub: Loki, seven days of logs, the MCP endpoint"
warn "and the wall. Any attendee who has not run step 06 loses their log tools."
say ""
say "Before you do this, check you gave them notice — two days beforehand,"
say "pointing at 'make step-06'. See docs/AFTER.md."
printf '\n'

if [[ -z "${DEMO_AUTO-}" && -t 0 ]]; then
  printf '%s%sType the hub name to confirm deletion: %s' "$BOLD" "$YELLOW" "$RESET"
  read -r CONFIRM < /dev/tty || true
  if [[ "$CONFIRM" != "$HUB_NAME" ]]; then
    ok "not deleting anything"
    exit 0
  fi
fi

# Same trap as the attendee cleanup: Civo leaves a cluster's volumes behind,
# and the hub's Loki volume is 20GB.
VOLS=$(civo_cluster_volumes "$CID" "$REGION")
[[ -n "$VOLS" ]] && note "$(echo "$VOLS" | wc -l) volume(s) will need removing after the cluster"

run "civo kubernetes remove '$CID' --region '$REGION' --yes"

for v in $VOLS; do
  run "civo volume remove '$v' --region '$REGION' --yes || true"
done

say ""
say "The LoadBalancers for the MCP endpoint and the wall are deleted with the"
say "cluster. Confirm, because they bill separately if they are ever orphaned:"
run "civo loadbalancer ls --region '$REGION' || true"
say ""
say "And any volumes left unattached:"
ORPHANS=$(civo_orphan_volumes "$REGION")
[[ -n "$ORPHANS" ]] && echo "$ORPHANS" || ok "none"

rm -f "$STATE/hub.kubeconfig" "$STATE/mcp-endpoint" "$STATE/sink-endpoint"
printf '\n'
ok "Hub torn down."
note "the token files in $STATE are now dead; delete them when you are ready"
