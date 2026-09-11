#!/usr/bin/env bash
# Prereq check. This runs first, on the attendee's own laptop, and is the
# single highest-value script in the repo: it turns "it doesn't work" into a
# specific missing tool with a copy-pasteable fix.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

banner "Workshop prerequisites"

FAILED=0
OS="$(uname -s)"
case "$OS" in
  Darwin) PKG="brew install" ;;
  Linux)  PKG="see link" ;;
  *)      PKG="see link" ;;
esac

# check <bin> <min-version> <version-command> <install hint>
check() {
  local bin="$1" min="$2" vercmd="$3" hint="$4" ver
  printf '  %-12s ' "$bin"
  if ! command -v "$bin" >/dev/null 2>&1; then
    printf '%s%smissing%s  -> %s\n' "$BOLD" "$RED" "$RESET" "$hint"; FAILED=1; return
  fi
  # No `head -1` before grep: kubectl prints "clientVersion:" first, so the
  # version is never on line one. And `|| true`, because a grep that matches
  # nothing exits 1, which under `set -e` kills the script instead of falling
  # through to the "version unknown" branch below.
  ver="$(eval "$vercmd" 2>/dev/null | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1 || true)"
  if [[ -z "$ver" ]]; then
    printf '%s%sfound%s (version unknown)\n' "$GREEN" "$BOLD" "$RESET"; return
  fi
  # Numeric compare on major.minor. These are deliberately separate statements:
  # bash expands every word of a `local` line before assigning any of them, so
  # `local a=$x b=${a#...}` reads `a` while it is still unset.
  local have_maj have_min want_maj want_min rest
  have_maj="${ver%%.*}"
  rest="${ver#*.}"
  have_min="${rest%%.*}"
  want_maj="${min%%.*}"
  rest="${min#*.}"
  want_min="${rest%%.*}"
  if (( have_maj > want_maj )) || { (( have_maj == want_maj )) && (( have_min >= want_min )); }; then
    printf '%s%s%-10s%s ok (need >= %s)\n' "$BOLD" "$GREEN" "$ver" "$RESET" "$min"
  else
    printf '%s%s%-10s%s too old, need >= %s  -> %s\n' "$BOLD" "$YELLOW" "$ver" "$RESET" "$min" "$hint"; FAILED=1
  fi
}

say "Checking the tools this workshop needs. Everything runs from your laptop"
say "against your own Civo cluster -- nothing is installed system-wide."
printf '\n'

check kubectl 1.28 "kubectl version --client -o json | grep gitVersion" \
  "https://kubernetes.io/docs/tasks/tools/  (macOS: brew install kubectl)"
check helm    3.14 "helm version --short" \
  "https://helm.sh/docs/intro/install/  (macOS: brew install helm)"
check civo    1.0  "civo version" \
  "https://github.com/civo/cli#set-up  (macOS: brew install civo)"
check jq      1.6  "jq --version" \
  "https://jqlang.github.io/jq/download/  (macOS: brew install jq)"
check curl    7.0  "curl --version" \
  "should be preinstalled; on Debian/Ubuntu: apt install curl"
check git     2.30 "git --version" \
  "https://git-scm.com/downloads"

printf '\n'
say "Checking credentials..."
printf '\n'

# Two tiers. You need the first before the day; the second is handed out in
# the room, so missing values there are a note, not a failure.
cred() {
  local name="$1" required="$2"
  printf '  %-22s ' "$name"
  if [[ -n "${!name-}" ]]; then
    printf '%s%sset%s (%s...)\n' "$BOLD" "$GREEN" "$RESET" "${!name:0:6}"
  elif [[ "$required" == "required" ]]; then
    printf '%s%smissing%s  -> add it to .env\n' "$BOLD" "$RED" "$RESET"; FAILED=1
  else
    printf '%s%snot yet%s  -> you get this at the workshop\n' "$DIM" "$YELLOW" "$RESET"
  fi
}
if [[ ! -f "$REPO_ROOT/.env" ]]; then
  fail ".env not found"
  note "cp .env.example .env  then add your Civo API key"
  FAILED=1
else
  cred CIVO_API_KEY required
  printf '\n'
  say "These are handed out in the room — you do not need them yet:"
  printf '\n'
  cred RELAX_API_KEY later
  cred MCP_ENDPOINT later
  cred MCP_TOKEN later
fi

printf '\n'
if (( FAILED )); then
  fail "Some prerequisites are missing -- fix the items above, then re-run: make doctor"
  exit 1
fi
ok "You are ready for the workshop."
printf '\n'
say "On the day, the first thing you will do is open the credentials page shown"
say "on the slides and download a filled-in .env. Then 'make step-01'."
