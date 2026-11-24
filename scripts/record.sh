#!/usr/bin/env bash
# Record the build as terminal GIFs for the slide deck.
#
#   scripts/record.sh            record all five
#   scripts/record.sh 0          just the cluster being created
#   scripts/record.sh 1          just the kagent install
#   scripts/record.sh 2 3 4      just the agents
#
# The room plays on a hub that is already built. These recordings are how the
# deck shows it being built anyway: the real steps, run for real against the
# real hub, captured once and played back full screen.
#
#   0  terraform  create a cluster, show it is empty (scripts/demo-cluster.sh)
#   1  hub-08     install kagent behind its guard, connect the logs
#   2  agent-01   log-reader
#   3  agent-02   log-detective
#   4  agent-03   early-warning
#
# Recordings 0 and 1 are cut into one GIF per section (demo-kagent-1-1.gif,
# -1-2.gif, ...), wherever the step clears the screen, so each section sits on
# its own slide and you move on when you have finished talking. If the number
# of sections changes, change the lists in slides/src/slides/index.jsx to match.
#
# Recording 0 is the odd one out. It does not touch the hub: it runs a real
# `terraform apply` that creates a second, three-node cluster, shows that it
# is empty, and destroys it again. That takes a few minutes, costs a few
# minutes of three nodes, and needs terraform installed. Without terraform a
# plain `make record` skips it and says so.
#
# The recordings show a build from nothing, so kagent is uninstalled from the
# hub before recording 1 (taking every agent and all chat history with it), and each
# agent is deleted immediately before its own recording and created again by
# it. Any agent that was not re-recorded is put back at the end. Do this before
# the event, not during it -- anyone mid-chat with an agent loses the
# conversation.
#
# Left out of the recordings on purpose (DEMO_RECORD in scripts/lib.sh): the
# step banner, and the guard in front of kagent. The guard is still installed
# and still tested while recording; it is just not on screen.
#
# Needs asciinema (records) and agg (renders the GIF):
#   https://docs.asciinema.org   https://docs.asciinema.org/manual/agg/
#
# Sized for a 1920x1080 slide. If the GIF comes out a different shape, adjust
# RECORD_COLS / RECORD_ROWS / RECORD_FONT_SIZE; the slide letterboxes rather
# than stretches, so a near miss still looks right.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

COLS="${RECORD_COLS:-112}"
ROWS="${RECORD_ROWS:-27}"
FONT_SIZE="${RECORD_FONT_SIZE:-28}"
PACE="${RECORD_PACE:-2}"               # seconds each command is held before it runs
IDLE="${RECORD_IDLE_LIMIT:-2}"         # longer silences are cut to this
# background, foreground, then the 8 ANSI colours: black so the recording has
# no visible edge on the slide, green and cyan from the deck's own palette.
THEME="${RECORD_THEME:-000000,d1ccbe,000000,ff5f56,00ff6f,ffbd2e,6ea8e0,d46ffe,33b7a3,ffffff}"
OUT="$REPO_ROOT/slides/src/assets"
CASTS="$REPO_ROOT/.state/casts"

export KUBECONFIG="$REPO_ROOT/.state/hub.kubeconfig"
[[ -f "$KUBECONFIG" ]] || { fail "no hub kubeconfig — build the hub first (make hub-all)"; exit 1; }
MISSING=""
for tool in asciinema agg; do command -v "$tool" >/dev/null 2>&1 || MISSING+=" $tool"; done
if [[ -n "$MISSING" ]]; then
  fail "missing:$MISSING"
  note "asciinema records the terminal, agg turns the recording into a GIF"
  exit 1
fi

mkdir -p "$OUT" "$CASTS"
cd "$REPO_ROOT"

# asciinema 3 renamed the size option.
if asciinema rec --help 2>&1 | grep -q -- '--window-size'; then
  SIZE_ARGS=(--window-size "${COLS}x${ROWS}")
else
  SIZE_ARGS=(--cols "$COLS" --rows "$ROWS")
fi

# What each recording runs. DEMO_AUTO removes the press-enter pauses, DEMO_PACE
# puts a readable beat back in their place, and DEMO_CLEAR_SECTIONS gives each
# section of a step a clean screen.
RECORD_ENV="DEMO_AUTO=1 DEMO_RECORD=1 DEMO_PACE=$PACE DEMO_CLEAR_SECTIONS=1 DEMO_NARROW=1 TERM=xterm-256color"
declare -A CMD=(
  [0]="bash scripts/demo-cluster.sh"
  [1]="bash hub/step-08-kagent/run.sh"
  [2]="bash scripts/add-agent.sh 01"
  [3]="bash scripts/add-agent.sh 02"
  [4]="bash scripts/add-agent.sh 03"
)
declare -A AGENT_FILE=( [2]=01 [3]=02 [4]=03 )

WHICH=("$@")
if (( ! ${#WHICH[@]} )); then
  WHICH=(1 2 3 4)
  if command -v terraform >/dev/null 2>&1; then
    WHICH=(0 1 2 3 4)
  else
    warn "terraform is not installed — skipping recording 0 (the cluster being created)"
  fi
fi
for n in "${WHICH[@]}"; do
  [[ -n "${CMD[$n]-}" ]] || { fail "no recording number $n (0-4)"; exit 1; }
  if [[ "$n" == 0 ]]; then
    command -v terraform >/dev/null 2>&1 || { fail "recording 0 needs terraform"; exit 1; }
  elif [[ "$n" != 1 ]]; then
    kubectl -n kagent get deploy kagent-controller >/dev/null 2>&1 \
      || { fail "kagent is not installed on the hub — run 'make hub-08' or 'make record N=1' first"; exit 1; }
  fi
done

if [[ -z "${RECORD_YES-}" ]]; then
  warn "Recording uninstalls kagent and its agents first, and installs them again."
  note "Fine before the event. Not while people are playing."
  [[ " ${WHICH[*]} " == *" 0 "* ]] && note "Recording 0 also creates a second cluster for a few minutes, then deletes it."
  if [[ -t 0 ]]; then
    printf '%s%sType yes to go ahead: %s' "$BOLD" "$YELLOW" "$RESET"
    read -r REPLY < /dev/tty || true
    [[ "$REPLY" == "yes" ]] || { ok "nothing recorded, nothing deleted"; exit 0; }
  else
    fail "no terminal to confirm on — set RECORD_YES=1 to go ahead unattended"; exit 1
  fi
fi

# --no-loop: the GIF plays once and holds its last frame, which is the state
# you want on screen while you talk about what just happened.
render() {  # cast, gif
  agg --quiet --no-loop --theme "$THEME" --font-size "$FONT_SIZE" \
      --cols "$COLS" --rows "$ROWS" \
      --idle-time-limit "$IDLE" --last-frame-duration 5 "$1" "$2"
  ok "$(basename "$2")  $(du -h "$2" | cut -f1)"
}

for n in "${WHICH[@]}"; do
  cast="$CASTS/kagent-$n.cast"

  if [[ "$n" == 0 ]]; then
    :   # nothing on the hub to reset
  elif [[ -n "${AGENT_FILE[$n]-}" ]]; then
    f=(agents/"${AGENT_FILE[$n]}"-*.yaml)
    name="$(sed -n 's/^  name: //p' "${f[0]}" | head -1)"
    kubectl -n kagent delete agent "$name" --ignore-not-found --wait=true >/dev/null
  else
    # The install is recorded as a first install, so kagent is taken off the
    # hub completely beforehand: Helm then says "installed" rather than
    # "upgraded", and every pod in the listing is seconds old. Chat history
    # goes with it. hub-08 puts all of it back, on screen.
    kubectl -n kagent delete agents.kagent.dev --all --wait=true >/dev/null 2>&1 || true
    kubectl -n kagent delete remotemcpservers.kagent.dev --all --wait=true >/dev/null 2>&1 || true
    kubectl -n kagent delete deploy kagent-guard --ignore-not-found >/dev/null
    helm -n kagent uninstall kagent --wait --timeout 5m >/dev/null 2>&1 || true
    helm -n kagent uninstall kagent-crds --wait --timeout 5m >/dev/null 2>&1 || true
    kubectl -n kagent delete pvc --all --wait=true >/dev/null 2>&1 || true
    wait_for "kagent's pods to go" 300 \
      "[[ \$(kubectl -n kagent get pods --no-headers 2>/dev/null | wc -l) -eq 0 ]]"
  fi

  printf '\n%s%s● recording %s%s  %s\n' "$BOLD" "$RED" "$n" "$RESET" "${CMD[$n]}"
  # asciinema does not pass on the exit status of what it recorded, so the
  # command leaves it in a file.
  rm -f "$CASTS/status"
  asciinema rec --overwrite --quiet "${SIZE_ARGS[@]}" \
    --command "sh -c 'env $RECORD_ENV ${CMD[$n]}; echo \$? > $CASTS/status'" "$cast" || true
  if [[ "$(cat "$CASTS/status" 2>/dev/null)" != 0 ]]; then
    fail "recording $n: the step failed — see it by running: ${CMD[$n]}"
    exit 1
  fi

  if [[ "$n" == 0 || "$n" == 1 ]]; then
    rm -f "$CASTS"/kagent-"$n"-*.cast "$OUT"/demo-kagent-"$n".gif "$OUT"/demo-kagent-"$n"-*.gif
    PARTS=$(python3 "$REPO_ROOT/scripts/split-cast.py" "$cast" "$CASTS/kagent-$n")
    for (( i = 1; i <= PARTS; i++ )); do
      render "$CASTS/kagent-$n-$i.cast" "$OUT/demo-kagent-$n-$i.gif"
    done
    note "recording $n is in $PARTS parts"
  else
    render "$cast" "$OUT/demo-kagent-$n.gif"
  fi
done

# Put back any agent that recording 1 took away and nothing re-created.
for f in agents/*.yaml; do
  name="$(sed -n 's/^  name: //p' "$f" | head -1)"
  kubectl -n kagent get agent "$name" >/dev/null 2>&1 && continue
  kubectl apply -f "$f" >/dev/null
  wait_for "$name to be ready again" 240 \
    "[[ \"\$(kubectl -n kagent get agent '$name' -o jsonpath='{.status.conditions[?(@.type==\"Ready\")].status}' 2>/dev/null)\" == 'True' ]]"
done

printf '\n'
ok "Recordings are in slides/src/assets/."
note "They are picked up by name: rebuild the deck (make hub-10)"
note "and check each one on its slide. Raw casts are kept in .state/casts/."
