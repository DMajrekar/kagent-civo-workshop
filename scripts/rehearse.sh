#!/usr/bin/env bash
# Run the whole attendee path with no pauses, timing each step.
#
# This is the check that matters before the event: if it passes end to end from
# a deleted cluster, the live run will not surprise you. It also produces the
# numbers to argue with docs/RUNSHEET.md about.
#
#   ./scripts/rehearse.sh              every step, stopping at the first failure
#   ./scripts/rehearse.sh -k           keep going after a failure
#   ./scripts/rehearse.sh 04 05        just these
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
export DEMO_AUTO=1

KEEP_GOING=""
if [[ "${1-}" == "-k" || "${1-}" == "--keep-going" ]]; then KEEP_GOING=1; shift; fi

STEPS=("$@")
[[ ${#STEPS[@]} -eq 0 ]] && STEPS=(01 02 03 04 05 06)

# Budgeted minutes, from the run sheet.
budget_for() {
  case "$1" in
    01) echo 2 ;; 02) echo 7 ;; 03) echo 9 ;;
    04) echo 13 ;; 05) echo 10 ;; 06) echo 6 ;;
    *)  echo 0 ;;
  esac
}

LOGDIR="${REHEARSE_LOGS:-$REPO_ROOT/.state/rehearsal}"
mkdir -p "$LOGDIR"
RESULTS=()
TOTAL=0
FAILED=0

banner "Rehearsal — the attendee path, timed"
say "No pauses. Every step runs as an attendee would run it, and each is timed"
say "against its slot in the run sheet."
printf '\n'

for s in "${STEPS[@]}"; do
  printf '%s%s── step-%s ─────────────────────────────────────────────%s\n' "$BOLD" "$BLUE" "$s" "$RESET"
  log="$LOGDIR/step-$s.log"
  start=$SECONDS
  if make "step-$s" > "$log" 2>&1; then
    rc=0
  else
    rc=$?
    FAILED=$((FAILED + 1))
  fi
  elapsed=$((SECONDS - start))
  TOTAL=$((TOTAL + elapsed))
  mins=$((elapsed / 60)); secs=$((elapsed % 60))
  bud=$(budget_for "$s")
  if (( rc != 0 )); then
    fail "step-$s FAILED after ${mins}m${secs}s — see $log"
    tail -15 "$log" | sed 's/^/    /'
    if [[ -z "$KEEP_GOING" ]]; then
      printf '\n'
      # Later steps build on this one. Carrying on produces timings for work
      # that was really done by the step that failed, which reads as a pass.
      fail "stopping here — later steps depend on this one."
      note "re-run with -k to continue anyway"
      RESULTS+=("$s|$elapsed|$(budget_for "$s")|$rc")
      break
    fi
  elif (( bud > 0 && elapsed > bud * 60 )); then
    warn "step-$s took ${mins}m${secs}s (budget ${bud}m) — over"
  else
    ok "step-$s took ${mins}m${secs}s (budget ${bud}m)"
  fi
  RESULTS+=("$s|$elapsed|$bud|$rc")
done

printf '\n'
banner "Rehearsal result"
printf '  %-8s %10s %10s   %s\n' "step" "actual" "budget" ""
for r in "${RESULTS[@]}"; do
  IFS='|' read -r s e b rc <<< "$r"
  mark="$GREEN ok $RESET"
  (( rc != 0 )) && mark="$RED FAIL$RESET"
  (( rc == 0 && b > 0 && e > b * 60 )) && mark="$YELLOW over$RESET"
  printf '  step-%-4s %7dm%02ds %8dm    %b\n' "$s" $((e / 60)) $((e % 60)) "$b" "$mark"
done
printf '\n  %-8s %7dm%02ds\n' "total" $((TOTAL / 60)) $((TOTAL % 60))
printf '\n'
note "Back-to-back timings run hot: in the session step-02 starts ~8 minutes"
note "after step-01, so the cluster is already up and step-02 does not pay for"
note "the wait. Read step-02 as an upper bound."
printf '\n'
if (( FAILED )); then
  fail "$FAILED step(s) failed — logs in $LOGDIR"
  exit 1
fi
ok "Every step passed. Logs in $LOGDIR"
