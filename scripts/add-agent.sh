#!/usr/bin/env bash
# Add one of the prepared agents to kagent on the hub, live.
#
#   scripts/add-agent.sh 02        applies agents/02-*.yaml
#   scripts/add-agent.sh --clear   takes every agent away again
#
# Meant to be run on the projector between the two rounds: it shows the
# manifest, applies it, and waits until the agent can actually answer. The CTF
# page asks kagent what agents exist every few seconds, so there is nothing
# else to do -- it appears on every player's phone by itself.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

export KUBECONFIG="$REPO_ROOT/.state/hub.kubeconfig"
cd "$REPO_ROOT"
[[ -f "$KUBECONFIG" ]] || { fail "no hub kubeconfig — run 'make hub-01' first"; exit 1; }

if [[ "${1-}" == "--clear" ]]; then
  kubectl -n kagent delete agents.kagent.dev --all
  exit 0
fi

N="${1-}"
shopt -s nullglob
FILES=("$REPO_ROOT"/agents/"$N"-*.yaml)
if [[ -z "$N" || ${#FILES[@]} -eq 0 ]]; then
  fail "no such agent: agents/${N}-*.yaml"
  note "available: $(cd "$REPO_ROOT/agents" && echo *.yaml)"
  exit 1
fi
F="${FILES[0]}"
NAME="$(sed -n 's/^  name: //p' "$F" | head -1)"

# Comments stripped: the file's header is a note to the presenter, and the
# room should be reading the spec.
# Not when recording: the manifest is longer than the recorded screen, and the
# slide before the recording already shows the part of it that matters.
if [[ -z "${DEMO_RECORD-}" ]]; then
  printf '\n%s# agents/%s%s\n' "$DIM" "$(basename "$F")" "$RESET"
  grep -v '^\s*#' "$F"
  printf '\n'
fi

[[ -n "${DEMO_AUTO-}" ]] && sleep "${DEMO_PACE:-0}"
run "kubectl apply -f agents/$(basename "$F")"
wait_for "$NAME to be ready" 240 \
  "[[ \"\$(kubectl -n kagent get agent '$NAME' -o jsonpath='{.status.conditions[?(@.type==\"Ready\")].status}' 2>/dev/null)\" == 'True' ]]" \
  || { kubectl -n kagent get agent "$NAME" \
         -o jsonpath='{range .status.conditions[*]}{.type}={.status} {.message}{"\n"}{end}'; exit 1; }

run "kubectl -n kagent get agent $NAME"
# An agent is not only a row in a table: kagent starts a pod for each one.
run "kubectl -n kagent get pods -l kagent=$NAME"
ok "$NAME is live"
