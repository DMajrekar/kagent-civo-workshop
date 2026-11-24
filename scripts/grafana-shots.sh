#!/usr/bin/env bash
# Retake the Grafana screenshots in the slide deck, against this hub.
#
#   scripts/grafana-shots.sh
#
# Needs no browser on your machine: it runs a headless one in a pod on the
# hub, points it at Grafana's public address, and copies two PNGs back into
# slides/src/assets/. Run `make hub-10` afterwards to put them in the deck.
#
# It prints where the query box and time picker are. If Grafana's layout has
# changed, copy those numbers into slides/src/slides/GrafanaSlides.jsx.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
export KUBECONFIG="$REPO_ROOT/.state/hub.kubeconfig"
GRAFANA="$(cat "$REPO_ROOT/.state/grafana-endpoint" 2>/dev/null || true)"
[[ -n "$GRAFANA" ]] || { fail "no Grafana address — run 'make hub-09' first"; exit 1; }
PW="${PLAYWRIGHT_VERSION:-1.49.1}"
NS=slides; POD=grafana-shots

kubectl -n "$NS" delete pod "$POD" --ignore-not-found >/dev/null
trap 'kubectl -n "$NS" delete pod "$POD" --ignore-not-found --wait=false >/dev/null' EXIT
kubectl -n "$NS" run "$POD" --image="mcr.microsoft.com/playwright:v${PW}-noble" --restart=Never --command -- sleep 1800
kubectl -n "$NS" wait --for=condition=Ready "pod/$POD" --timeout=600s
kubectl -n "$NS" exec "$POD" -- sh -c "mkdir -p /w && cd /w && npm init -y >/dev/null && npm i --silent playwright@$PW"
kubectl -n "$NS" cp "$REPO_ROOT/scripts/grafana-shots.js" "$POD:/w/shots.js"
kubectl -n "$NS" exec "$POD" -- sh -c "cd /w && GRAFANA='${GRAFANA%/}' node shots.js"
for f in grafana-explore.png grafana-time.png; do
  kubectl -n "$NS" cp "$POD:/w/$f" "$REPO_ROOT/slides/src/assets/$f" >/dev/null
done
ok "screenshots are in slides/src/assets/ — 'make hub-10' puts them in the deck"
