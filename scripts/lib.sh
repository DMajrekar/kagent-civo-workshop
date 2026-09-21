#!/usr/bin/env bash
# Shared presentation helpers for the kagent workshop.
#
# Every step script sources this. The model is: narrate, show the command,
# wait for the presenter to hit enter, run it, show the result.
#
#   DEMO_AUTO=1   skip every pause (use this to rehearse the whole workshop
#                 unattended, and in CI -- if it passes with DEMO_AUTO=1 it
#                 will not surprise you on stage)
#   DEMO_NARROW=1 wrap narration at 72 cols instead of terminal width

set -euo pipefail

# Colour names are short and generic, which means they can silently clobber a
# variable the caller set on the command line. RESET in particular reads like a
# perfectly good flag name. Warn rather than swallow it.
for _c in BOLD DIM RESET RED GREEN YELLOW BLUE CYAN; do
  if [[ -n "${!_c-}" ]]; then
    printf 'lib.sh: ignoring inherited $%s — it is a colour variable here.\n' "$_c" >&2
    printf '        If you meant a control flag, it needs a different name.\n' >&2
  fi
done
unset _c

if [[ -t 1 ]]; then
  BOLD=$'\033[1m'; DIM=$'\033[2m'; RESET=$'\033[0m'
  RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'
  BLUE=$'\033[34m'; CYAN=$'\033[36m'
else
  BOLD=; DIM=; RESET=; RED=; GREEN=; YELLOW=; BLUE=; CYAN=
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export REPO_ROOT

# Scratch space for kubeconfigs, generated manifests and tokens. Gitignored.
# Created here rather than per-step: several steps write into it and used to
# depend on an earlier one having made it first.
mkdir -p "$REPO_ROOT/.state"

# ---------------------------------------------------------------- env loading

# Load .env if present. Values already in the environment win, so you can
# override a single var for one run without editing the file.
load_env() {
  local envfile="${1:-$REPO_ROOT/.env}"
  [[ -f "$envfile" ]] || return 0
  local line key val
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ "$line" =~ ^[[:space:]]*$ ]] && continue
    line="${line#export }"
    key="${line%%=*}"; val="${line#*=}"
    key="$(printf '%s' "$key" | tr -d '[:space:]')"
    [[ -z "$key" ]] && continue
    # strip surrounding quotes
    val="${val%\"}"; val="${val#\"}"; val="${val%\'}"; val="${val#\'}"
    [[ -n "${!key-}" ]] || export "$key=$val"
  done < "$envfile"
}

# Fail loudly and early if a step needs a variable the presenter has not set.
require_env() {
  local missing=()
  for v in "$@"; do [[ -n "${!v-}" ]] || missing+=("$v"); done
  if (( ${#missing[@]} )); then
    printf '\n%s%sMissing required variable(s):%s %s\n' "$BOLD" "$RED" "$RESET" "${missing[*]}"
    printf '  Set them in %s/.env (copy .env.example to start).\n\n' "$REPO_ROOT"
    exit 1
  fi
}

# ------------------------------------------------------------------ narration

_width() {
  if [[ -n "${DEMO_NARROW-}" ]]; then echo 72
  else local c; c=$(tput cols 2>/dev/null || echo 80); (( c > 100 )) && c=100; echo "$c"; fi
}

banner() {
  local w; w=$(_width)
  printf '\n%s%s%s%s\n' "$BOLD" "$BLUE" "$(printf '%*s' "$w" '' | tr ' ' '=')" "$RESET"
  printf '%s%s  %s%s\n' "$BOLD" "$BLUE" "$*" "$RESET"
  printf '%s%s%s%s\n\n' "$BOLD" "$BLUE" "$(printf '%*s' "$w" '' | tr ' ' '=')" "$RESET"
}

# A narration paragraph -- what you say while the slide is up.
say()  { printf '%s\n' "$*" | fold -s -w "$(_width)"; }
note() { printf '%s%s  %s%s\n' "$DIM" "$CYAN" "$*" "$RESET"; }
warn() { printf '%s%s!! %s%s\n' "$BOLD" "$YELLOW" "$*" "$RESET"; }
ok()   { printf '%s%s✓ %s%s\n' "$BOLD" "$GREEN" "$*" "$RESET"; }
fail() { printf '%s%s✗ %s%s\n' "$BOLD" "$RED" "$*" "$RESET"; }

# ---------------------------------------------------------------- interaction

pause() {
  [[ -n "${DEMO_AUTO-}" ]] && return 0
  [[ -t 0 ]] || return 0
  printf '\n%s%s  [enter] %s%s' "$DIM" "$CYAN" "${1:-continue}" "$RESET"
  read -r _ < /dev/tty || true
  printf '\n'
}

# run "<command>" -- show it, wait for enter, execute it, report.
#
# NOTE: run and run_quiet ALREADY pause. Never put a bare `pause` immediately
# before one, or the presenter has to press enter twice for a single action.
# Use `pause` only where nothing is about to be run -- to hold on a point, or
# to confirm something done outside the script.
# The command is displayed exactly as the attendee would type it, which is the
# whole point: they are reading along and copying from their own repo.
run() {
  local cmd="$*"
  printf '\n%s%s$ %s%s' "$BOLD" "$GREEN" "$cmd" "$RESET"
  if [[ -z "${DEMO_AUTO-}" && -t 0 ]]; then read -r _ < /dev/tty || true; else printf '\n'; fi
  printf '\n'
  local rc=0
  eval "$cmd" || rc=$?
  if (( rc != 0 )); then
    printf '\n'; fail "command exited $rc"
    [[ -n "${DEMO_CONTINUE_ON_ERROR-}" ]] || exit $rc
  fi
  return 0
}

# Like run, but the output is noisy/uninteresting -- swallow it unless it fails.
run_quiet() {
  local cmd="$*"
  printf '\n%s%s$ %s%s' "$BOLD" "$GREEN" "$cmd" "$RESET"
  if [[ -z "${DEMO_AUTO-}" && -t 0 ]]; then read -r _ < /dev/tty || true; else printf '\n'; fi
  local out rc=0
  out="$(eval "$cmd" 2>&1)" || rc=$?
  if (( rc != 0 )); then printf '\n%s\n' "$out"; fail "command exited $rc"; exit $rc; fi
  ok "done"
}

# ------------------------------------------------------------ port-forwards
#
# `kubectl port-forward` exits if the pod is not accepting connections yet,
# which on a cold cluster it often is not even once the resource reports Ready.
# Backgrounding it with output discarded means you never see that -- you just
# watch a 60-second timeout and learn nothing. Start it, check the port really
# answers, and restart it if the process died.
#
#   port_forward <ns> <target> <local:remote> [attempts]
# Sets PF_PIDS so cleanup_port_forwards can tear them all down.
PF_PIDS=""

port_forward() {
  local ns="$1" target="$2" ports="$3" attempts="${4:-5}"
  local lport="${ports%%:*}"
  local i pid
  for (( i = 1; i <= attempts; i++ )); do
    kubectl -n "$ns" port-forward "$target" "$ports" >/dev/null 2>&1 &
    pid=$!
    local waited=0
    while (( waited < 15 )); do
      if ! kill -0 "$pid" 2>/dev/null; then break; fi
      if (echo > "/dev/tcp/127.0.0.1/$lport") >/dev/null 2>&1; then
        PF_PIDS="$PF_PIDS $pid"
        return 0
      fi
      sleep 1; waited=$(( waited + 1 ))
    done
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
    (( i < attempts )) && sleep 3
  done
  fail "could not port-forward to $target in namespace $ns after $attempts attempts"
  note "kubectl -n $ns get pod,endpoints -l ... to see whether it is actually serving"
  return 1
}

cleanup_port_forwards() {
  local p
  for p in $PF_PIDS; do kill "$p" 2>/dev/null || true; done
  PF_PIDS=""
}

# ------------------------------------------------------------------- waiting

# Poll until a command succeeds. Used so a step can be re-run safely while the
# thing it depends on (a cluster, a rollout) is still coming up.
# Return to the start of the line AND erase it. A bare \r only moves the
# cursor, so a short line written over a long one leaves the long one's tail
# visible.
_clearline() { printf '\r\033[2K'; }

wait_for() {
  local desc="$1" timeout="$2"; shift 2
  local deadline=$(( SECONDS + timeout )) spin='|/-\' i=0
  local tty=0; [[ -t 1 ]] && tty=1
  # Draw the spinner only on a terminal. Redirected to a file nothing
  # interprets \r, so the progress line and the result both survive and read
  # as duplicated text -- which is exactly how it looked in the run logs.
  if (( tty )); then
    printf '%s  waiting for %s (up to %ss)%s ' "$DIM" "$desc" "$timeout" "$RESET"
  fi
  while (( SECONDS < deadline )); do
    if eval "$@" >/dev/null 2>&1; then
      (( tty )) && _clearline
      ok "$desc"
      return 0
    fi
    (( tty )) && printf '\b%s' "${spin:i++%4:1}"
    sleep 5
  done
  (( tty )) && _clearline
  fail "timed out waiting for $desc"
  return 1
}

# ------------------------------------------------------------------ prereqs

need() {
  local bin="$1" hint="${2-}"
  if command -v "$bin" >/dev/null 2>&1; then return 0; fi
  fail "$bin not found"; [[ -n "$hint" ]] && note "$hint"
  return 1
}

load_env

# ------------------------------------------------------------ civo helpers
#
# `civo kubernetes show <name>` matches on PREFIX, not exact name: asking for
# "kagent-workshop" happily returns "kagent-workshop-hub". In a workshop where
# everyone picks their own cluster name and a shared hub exists in the same
# account, that is how somebody ends up deploying into the instructor's
# cluster. Always resolve to an ID by exact name.

# civo_cluster_id <name> <region> -> prints the ID, or nothing if no exact match
civo_cluster_id() {
  local name="$1" region="$2"
  civo kubernetes ls --region "$region" -o json 2>/dev/null \
    | NAME="$name" python3 -c '
import json, os, sys
want = os.environ["NAME"]
try:
    rows = json.load(sys.stdin) or []
except Exception:
    sys.exit(0)
for c in rows:
    if c.get("name") == want:
        print(c.get("id", "")); break
'
}

civo_cluster_exists() { [[ -n "$(civo_cluster_id "$1" "$2")" ]]; }

# civo_cluster_field <id> <region> <field>  e.g. Status
civo_cluster_field() {
  civo kubernetes show "$1" --region "$2" -o custom -f "$3" 2>/dev/null | tail -1
}

# civo_cluster_volumes <cluster-id> <region> -> volume IDs belonging to it
#
# Deleting a Civo cluster does NOT delete the volumes its PVCs created. They
# are left "available" and keep billing, and the only warning is a line in the
# delete output that scrolls past. Collect them before deleting the cluster --
# afterwards the association is gone and you cannot tell whose they were.
civo_cluster_volumes() {
  local cid="$1" region="$2"
  civo volume ls --region "$region" -o json 2>/dev/null \
    | CID="$cid" python3 -c '
import json, os, sys
want = os.environ["CID"]
try:
    rows = json.load(sys.stdin) or []
except Exception:
    sys.exit(0)
for v in rows:
    if v.get("cluster_id") == want or v.get("cluster") == want:
        print(v.get("id", ""))
'
}

# Report volumes with no cluster and no instance -- leftovers that still bill.
civo_orphan_volumes() {
  civo volume ls --region "${1:-lon1}" -o json 2>/dev/null \
    | python3 -c '
import json, sys
try:
    rows = json.load(sys.stdin) or []
except Exception:
    sys.exit(0)
for v in rows:
    if not (v.get("cluster_id") or v.get("cluster") or v.get("instance_id") or v.get("instance")):
        vid = v.get("id", "")
        name = v.get("name", "")
        size = v.get("size_gb", v.get("size", "?"))
        print("%s\t%s\t%sGB" % (vid, name, size))
'
}
