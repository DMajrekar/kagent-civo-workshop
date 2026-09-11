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
  ver="$(eval "$vercmd" 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1)"
  if [[ -z "$ver" ]]; then
    printf '%s%sfound%s (version unknown)\n' "$GREEN" "$BOLD" "$RESET"; return
  fi
  # numeric compare major.minor
  local have_maj="${ver%%.*}" rest="${ver#*.}" have_min="${rest%%.*}"
  local want_maj="${min%%.*}" wrest="${min#*.}" want_min="${wrest%%.*}"
  if (( have_maj > want_maj )) || { (( have_maj == want_maj )) && (( have_min >= want_min )); }; then
    printf '%s%s%-10s%s ok (need >= %s)\n' "$BOLD" "$GREEN" "$ver" "$RESET" "$min"
  else
    printf '%s%s%-10s%s too old, need >= %s  -> %s\n' "$BOLD" "$YELLOW" "$ver" "$RESET" "$min" "$hint"; FAILED=1
  fi
}

say "Checking the tools this workshop needs. Everything runs from your laptop"
say "against your own Civo cluster -- nothing is installed system-wide."
printf '\n'

check kubectl 1.28 "kubectl version --client -o yaml" \
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

cred() {
  local name="$1"
  printf '  %-22s ' "$name"
  if [[ -n "${!name-}" ]]; then
    printf '%s%sset%s (%s...)\n' "$BOLD" "$GREEN" "$RESET" "${!name:0:6}"
  else
    printf '%s%smissing%s  -> add it to .env\n' "$BOLD" "$RED" "$RESET"; FAILED=1
  fi
}
if [[ ! -f "$REPO_ROOT/.env" ]]; then
  fail ".env not found"
  note "cp .env.example .env  then fill in the values from your workshop card"
  FAILED=1
else
  cred CIVO_API_KEY
  cred RELAX_API_KEY
  cred MCP_ENDPOINT
  cred MCP_TOKEN
fi

printf '\n'
if (( FAILED )); then
  fail "Some prerequisites are missing -- fix the items above, then re-run: make doctor"
  exit 1
fi
ok "All prerequisites satisfied. Run 'make step-01' to create your cluster."
