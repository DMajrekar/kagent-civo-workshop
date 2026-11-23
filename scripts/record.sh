#!/usr/bin/env bash
# Record the kagent build as terminal GIFs for the slide deck.
#
#   scripts/record.sh            record all four
#   scripts/record.sh 1          just the kagent install
#   scripts/record.sh 2 3 4      just the agents
#
# The room plays on a hub that is already built. These recordings are how the
# deck shows it being built anyway: the real steps, run for real against the
# real hub, captured once and played back full screen.
#
#   1  hub-08     install kagent behind its guard, connect the logs
#   2  agent-01   log-reader
#   3  agent-02   log-detective
#   4  agent-03   early-warning
#
# Every step is idempotent, so recording 1 on a finished hub replays the
# install without changing anything. The agents are different: an agent that
# already exists applies as "unchanged", which is not what building it looks
# like. So each agent is deleted immediately before its recording and created
# again by it. Do this before the event, not during it -- anyone mid-chat with
# that agent loses the conversation.
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
kubectl -n kagent get deploy kagent-controller >/dev/null 2>&1 \
  || { fail "kagent is not installed on the hub — run 'make hub-08' once before recording it"; exit 1; }

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
RECORD_ENV="DEMO_AUTO=1 DEMO_PACE=$PACE DEMO_CLEAR_SECTIONS=1 DEMO_NARROW=1 TERM=xterm-256color"
declare -A CMD=(
  [1]="bash hub/step-08-kagent/run.sh"
  [2]="bash scripts/add-agent.sh 01"
  [3]="bash scripts/add-agent.sh 02"
  [4]="bash scripts/add-agent.sh 03"
)
declare -A AGENT_FILE=( [2]=01 [3]=02 [4]=03 )

WHICH=("$@"); (( ${#WHICH[@]} )) || WHICH=(1 2 3 4)

NEEDS_DELETE=0
for n in "${WHICH[@]}"; do [[ -n "${AGENT_FILE[$n]-}" ]] && NEEDS_DELETE=1; done
if (( NEEDS_DELETE )) && [[ -z "${RECORD_YES-}" ]]; then
  warn "Recording an agent deletes it first and creates it again."
  note "Fine before the event. Not while people are playing."
  if [[ -t 0 ]]; then
    printf '%s%sType yes to go ahead: %s' "$BOLD" "$YELLOW" "$RESET"
    read -r REPLY < /dev/tty || true
    [[ "$REPLY" == "yes" ]] || { ok "nothing recorded, nothing deleted"; exit 0; }
  else
    fail "no terminal to confirm on — set RECORD_YES=1 to go ahead unattended"; exit 1
  fi
fi

for n in "${WHICH[@]}"; do
  [[ -n "${CMD[$n]-}" ]] || { fail "no recording number $n (1-4)"; exit 1; }
  cast="$CASTS/kagent-$n.cast"
  gif="$OUT/demo-kagent-$n.gif"

  if [[ -n "${AGENT_FILE[$n]-}" ]]; then
    f=(agents/"${AGENT_FILE[$n]}"-*.yaml)
    name="$(sed -n 's/^  name: //p' "${f[0]}" | head -1)"
    kubectl -n kagent delete agent "$name" --ignore-not-found --wait=true >/dev/null
  fi

  printf '\n%s%s● recording %s%s  %s\n' "$BOLD" "$RED" "$n" "$RESET" "${CMD[$n]}"
  if ! asciinema rec --overwrite --quiet "${SIZE_ARGS[@]}" \
         --command "env $RECORD_ENV ${CMD[$n]}" "$cast"; then
    fail "recording $n: the step failed — see it by running: ${CMD[$n]}"
    exit 1
  fi

  # --no-loop: the GIF plays once and holds its last frame, which is the state
  # you want on screen while you talk about what just happened.
  agg --quiet --no-loop --theme "$THEME" --font-size "$FONT_SIZE" \
      --idle-time-limit "$IDLE" --last-frame-duration 5 "$cast" "$gif"
  ok "$(basename "$gif")  $(du -h "$gif" | cut -f1)"
done

printf '\n'
ok "Recordings are in slides/src/assets/."
note "They are picked up by name: rebuild the deck (cd slides && npm run build)"
note "and check each one on its slide. Raw casts are kept in .state/casts/."
