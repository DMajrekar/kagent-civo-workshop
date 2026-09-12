#!/usr/bin/env bash
# Open (or close) the kagent dashboard.
#
# Deliberately not a trapped port-forward inside a step: the steps clean theirs
# up on exit, and this one has to outlive the step that opened it so the UI
# stays usable for the rest of the session.
#
# Port 8082 is what the kagent docs use:
#   kubectl port-forward -n kagent service/kagent-ui 8082:8080
# The kagent CLI's `kagent dashboard` does the same thing and opens a browser.
#
#   scripts/ui.sh          start it, print the URL
#   scripts/ui.sh stop     close it
#   scripts/ui.sh status   is it up?
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

STATE="$REPO_ROOT/.state"
export KUBECONFIG="${KUBECONFIG:-$STATE/workshop.kubeconfig}"
PIDFILE="$STATE/ui.pid"
PORT="${UI_PORT:-8082}"
ACTION="${1:-start}"

alive() { [[ -s "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; }
answering() { curl -sf -o /dev/null --max-time 3 "http://127.0.0.1:$PORT/" 2>/dev/null; }

case "$ACTION" in
  stop)
    if alive; then kill "$(cat "$PIDFILE")" 2>/dev/null; ok "dashboard closed"
    else note "dashboard was not running"; fi
    rm -f "$PIDFILE"
    ;;
  status)
    if alive && answering; then ok "dashboard is up at http://localhost:$PORT"
    else note "dashboard is not running — start it with: make ui"; exit 1; fi
    ;;
  start)
    [[ -f "$KUBECONFIG" ]] || { fail "no kubeconfig — run 'make step-02' first"; exit 1; }
    if alive && answering; then
      ok "dashboard already open at http://localhost:$PORT"
      exit 0
    fi
    rm -f "$PIDFILE"
    # Survives this script exiting, which is the whole point.
    nohup kubectl -n kagent port-forward svc/kagent-ui "$PORT:8080" \
      >/dev/null 2>&1 < /dev/null &
    echo $! > "$PIDFILE"
    for _ in $(seq 1 20); do
      answering && break
      alive || { fail "port-forward died immediately"; \
                 note "is something else already using port $PORT? try: UI_PORT=8090 make ui"; \
                 rm -f "$PIDFILE"; exit 1; }
      sleep 1
    done
    if answering; then
      ok "dashboard open"
      note "http://localhost:$PORT"
      note "close it later with: make ui-stop"
    else
      fail "dashboard did not respond on port $PORT"
      kill "$(cat "$PIDFILE")" 2>/dev/null; rm -f "$PIDFILE"; exit 1
    fi
    ;;
  *) fail "usage: scripts/ui.sh [start|stop|status]"; exit 1 ;;
esac
