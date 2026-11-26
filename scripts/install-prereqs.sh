#!/usr/bin/env bash
# Install everything needed to build the hub and record the deck.
#
#   sudo scripts/install-prereqs.sh              everything
#   sudo WITH_GH=1 scripts/install-prereqs.sh    and the GitHub CLI
#
# For a fresh Ubuntu server (22.04 or 24.04, amd64 or arm64). Safe to run
# again: anything already installed is left alone. Tools go in /usr/local/bin
# or come from apt, so every user on the machine gets them.
#
# What it installs, and for what (see docs/HOSTING.md):
#   curl jq python3 git make   used by every hub step
#   kubectl, helm, civo        building the hub
#   asciinema, agg             make record
#   terraform                  make record N=0 only
#
# Versions are the ones the workshop was last built and recorded with.
# Override any of them from the environment.
set -euo pipefail

KUBECTL_VERSION="${KUBECTL_VERSION:-v1.35.10}"
HELM_VERSION="${HELM_VERSION:-v4.3.2}"
CIVO_VERSION="${CIVO_VERSION:-1.6.1}"
AGG_VERSION="${AGG_VERSION:-1.9.0}"
BIN=/usr/local/bin

say()  { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
ok()   { printf '    \033[32m✓\033[0m %s\n' "$*"; }
die()  { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

[[ $EUID -eq 0 ]] || die "run this with sudo"
[[ -r /etc/os-release ]] || die "cannot tell which OS this is"
. /etc/os-release
[[ "${ID:-}" == "ubuntu" ]] || die "this script is for Ubuntu (found: ${ID:-unknown})"

case "$(dpkg --print-architecture)" in
  amd64) ARCH=amd64; AGG_TARGET=x86_64-unknown-linux-gnu ;;
  arm64) ARCH=arm64; AGG_TARGET=aarch64-unknown-linux-gnu ;;
  *)     die "unsupported architecture: $(dpkg --print-architecture)" ;;
esac

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fetch() { curl -fsSL --retry 3 -o "$2" "$1"; }

export DEBIAN_FRONTEND=noninteractive

say "apt packages"
apt-get update -qq
apt-get install -y -qq ca-certificates curl gnupg jq python3 git make asciinema >/dev/null
ok "curl jq python3 git make asciinema"

say "kubectl $KUBECTL_VERSION"
if have kubectl; then ok "already installed: $(kubectl version --client 2>/dev/null | head -1)"
else
  fetch "https://dl.k8s.io/release/$KUBECTL_VERSION/bin/linux/$ARCH/kubectl" "$TMP/kubectl"
  fetch "https://dl.k8s.io/release/$KUBECTL_VERSION/bin/linux/$ARCH/kubectl.sha256" "$TMP/kubectl.sha256"
  echo "$(cat "$TMP/kubectl.sha256")  $TMP/kubectl" | sha256sum --check --quiet \
    || die "kubectl checksum did not match"
  install -m 0755 "$TMP/kubectl" "$BIN/kubectl"
  ok "installed"
fi

say "helm $HELM_VERSION"
if have helm; then ok "already installed: $(helm version --short 2>/dev/null)"
else
  fetch "https://get.helm.sh/helm-$HELM_VERSION-linux-$ARCH.tar.gz" "$TMP/helm.tgz"
  fetch "https://get.helm.sh/helm-$HELM_VERSION-linux-$ARCH.tar.gz.sha256sum" "$TMP/helm.sum"
  echo "$(awk '{print $1}' "$TMP/helm.sum")  $TMP/helm.tgz" | sha256sum --check --quiet \
    || die "helm checksum did not match"
  tar -xzf "$TMP/helm.tgz" -C "$TMP"
  install -m 0755 "$TMP/linux-$ARCH/helm" "$BIN/helm"
  ok "installed"
fi

say "civo $CIVO_VERSION"
if have civo; then ok "already installed: $(civo version 2>/dev/null | head -1)"
else
  REL="https://github.com/civo/cli/releases/download/v$CIVO_VERSION"
  TGZ="civo-$CIVO_VERSION-linux-$ARCH.tar.gz"
  fetch "$REL/$TGZ" "$TMP/$TGZ"
  fetch "$REL/civo-$CIVO_VERSION-checksums.sha256" "$TMP/civo.sums"
  ( cd "$TMP" && grep " $TGZ\$" civo.sums | sha256sum --check --quiet ) \
    || die "civo checksum did not match"
  tar -xzf "$TMP/$TGZ" -C "$TMP" civo
  install -m 0755 "$TMP/civo" "$BIN/civo"
  ok "installed"
fi

say "agg $AGG_VERSION"
# The project publishes no checksums, so this one is trusted on HTTPS alone.
if have agg; then ok "already installed: $(agg --version 2>/dev/null)"
else
  fetch "https://github.com/asciinema/agg/releases/download/v$AGG_VERSION/agg-$AGG_TARGET" "$TMP/agg"
  install -m 0755 "$TMP/agg" "$BIN/agg"
  ok "installed"
fi

say "terraform"
if have terraform; then ok "already installed: $(terraform version 2>/dev/null | head -1)"
else
  install -m 0755 -d /etc/apt/keyrings
  fetch https://apt.releases.hashicorp.com/gpg "$TMP/hashicorp.asc"
  gpg --dearmor --yes -o /etc/apt/keyrings/hashicorp.gpg "$TMP/hashicorp.asc"
  echo "deb [arch=$ARCH signed-by=/etc/apt/keyrings/hashicorp.gpg] https://apt.releases.hashicorp.com $VERSION_CODENAME main" \
    > /etc/apt/sources.list.d/hashicorp.list
  apt-get update -qq
  apt-get install -y -qq terraform >/dev/null
  ok "installed"
fi

if [[ -n "${WITH_GH-}" ]]; then
  say "gh"
  if have gh; then ok "already installed: $(gh --version 2>/dev/null | head -1)"
  else
    install -m 0755 -d /etc/apt/keyrings
    fetch https://cli.github.com/packages/githubcli-archive-keyring.gpg /etc/apt/keyrings/githubcli-archive-keyring.gpg
    chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=$ARCH signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list
    apt-get update -qq
    apt-get install -y -qq gh >/dev/null
    ok "installed"
  fi
fi

say "Installed"
for t in curl jq python3 git make kubectl helm civo asciinema agg terraform ${WITH_GH:+gh}; do
  if have "$t"; then printf '    \033[32m✓\033[0m %-10s %s\n' "$t" "$(command -v "$t")"
  else printf '    \033[31m✗\033[0m %-10s missing\n' "$t"; MISSING=1; fi
done
[[ -z "${MISSING-}" ]] || die "something did not install; see above"

printf '\nNext: cp .env.example .env, add your keys, then make hub-all (docs/HOSTING.md).\n'
