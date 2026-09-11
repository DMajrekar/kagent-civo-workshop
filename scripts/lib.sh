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

if [[ -t 1 ]]; then
  BOLD=$'\033[1m'; DIM=$'\033[2m'; RESET=$'\033[0m'
  RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'
  BLUE=$'\033[34m'; CYAN=$'\033[36m'
else
  BOLD=; DIM=; RESET=; RED=; GREEN=; YELLOW=; BLUE=; CYAN=
fi

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export REPO_ROOT

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

# run "<command>" -- show it, wait, execute it, report.
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

# ------------------------------------------------------------------- waiting

# Poll until a command succeeds. Used so a step can be re-run safely while the
# thing it depends on (a cluster, a rollout) is still coming up.
wait_for() {
  local desc="$1" timeout="$2"; shift 2
  local deadline=$(( SECONDS + timeout )) spin='|/-\' i=0
  printf '%s  waiting for %s (up to %ss)%s ' "$DIM" "$desc" "$timeout" "$RESET"
  while (( SECONDS < deadline )); do
    if eval "$@" >/dev/null 2>&1; then printf '\r'; ok "$desc"; return 0; fi
    printf '\b%s' "${spin:i++%4:1}"; sleep 5
  done
  printf '\r'; fail "timed out waiting for $desc"
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
