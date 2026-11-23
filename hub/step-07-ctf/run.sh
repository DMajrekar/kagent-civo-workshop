#!/usr/bin/env bash
# title: Deploy the CTF app
#
# The page the room plays on: join with an email, a sheet of flags, a
# scoreboard for the projector and a round control for you. It is also the
# gateway that tells the kagent ingress who each player is.
#
# Run it again after hub-09: it picks up the public HTTPS addresses from .state
# and bakes them into the links the page hands out.
source "$(dirname "${BASH_SOURCE[0]}")/../../scripts/lib.sh"

STATE="$REPO_ROOT/.state"
export KUBECONFIG="$STATE/hub.kubeconfig"
[[ -f "$KUBECONFIG" ]] || { fail "no hub kubeconfig — run 'make hub-01' first"; exit 1; }
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NS="${OBS_NAMESPACE:-observability}"
IMAGE="${CTF_IMAGE:-python:3.12-alpine}"
ROUND_SECONDS="${ROUND_SECONDS:-1200}"

banner "Hub — step 07: the CTF app"

say "One small Python server, standard library only. It holds the flags, the"
say "clock and the scores, and answers the kagent ingress's question about"
say "who is asking."

# ------------------------------------------------------------------- secrets
# Both generated once and kept, so a re-run never logs the room out or changes
# the key you have already typed into /admin.
SECRET_FILE="$STATE/ctf-secret"
ADMIN_FILE="$STATE/ctf-admin-key"
[[ -s "$SECRET_FILE" ]] || { head -c 32 /dev/urandom | base64 | tr -d '/+=\n' > "$SECRET_FILE"; chmod 600 "$SECRET_FILE"; }
if [[ -n "${CTF_ADMIN_KEY-}" ]]; then
  printf '%s' "$CTF_ADMIN_KEY" > "$ADMIN_FILE"
elif [[ ! -s "$ADMIN_FILE" ]]; then
  printf '%s-%s-%04d' "$(shuf -n1 -e amber cedar ember fjord grove onyx ridge tidal)" \
    "$(shuf -n1 -e anvil beacon delta falcon harbor otter summit willow)" "$((RANDOM % 10000))" > "$ADMIN_FILE"
fi
chmod 600 "$ADMIN_FILE"
ADMIN_KEY="$(cat "$ADMIN_FILE")"

# ----------------------------------------------------------------- addresses
# Written by hub-09. Empty on a first pass, which is fine: the app runs, the
# links are just not public yet.
PUB_URL="$(cat "$STATE/ctf-endpoint" 2>/dev/null || true)"
KAGENT_URL="$(cat "$STATE/kagent-endpoint" 2>/dev/null || true)"
GRAF_URL="$(cat "$STATE/grafana-explore-url" 2>/dev/null || true)"
[[ -n "$PUB_URL" ]] || note "no public address yet — hub-09 sets it and re-runs this step"

run_quiet "kubectl -n '$NS' create secret generic ctf \
  --from-file=secret='$SECRET_FILE' \
  --from-file=admin-key='$ADMIN_FILE' \
  --dry-run=client -o yaml | kubectl apply -f -"

run_quiet "kubectl -n '$NS' create configmap ctf \
  --from-file=ctf.py='$HERE/ctf.py' \
  --dry-run=client -o yaml | kubectl apply -f -"

# The Grafana deep link is long and full of characters YAML has opinions
# about, so let Python quote every value rather than trusting a heredoc.
python3 - "$STATE/ctf.yaml" <<PYEOF
import hashlib, json, sys
ns = "${NS}"
env = {
    "PORT": "8080", "PYTHONUNBUFFERED": "1", "DATA_PATH": "/data/ctf.json",
    "ROUND_SECONDS": "${ROUND_SECONDS}",
    "PUBLIC_URL": """${PUB_URL}""",
    "KAGENT_URL": """${KAGENT_URL}""",
    "GRAFANA_URL": """${GRAF_URL}""",
    "KAGENT_API": "http://kagent-controller.kagent.svc.cluster.local:8083/api",
    "CTF_TITLE": """${CTF_TITLE:-Your cluster called}""",
}
notice = """${JOIN_NOTICE-}"""
if notice:
    env["JOIN_NOTICE"] = notice
envs = [{"name": k, "value": v} for k, v in env.items()]
envs += [{"name": "CTF_SECRET", "valueFrom": {"secretKeyRef": {"name": "ctf", "key": "secret"}}},
         {"name": "ADMIN_KEY", "valueFrom": {"secretKeyRef": {"name": "ctf", "key": "admin-key"}}}]
docs = [
    # Players, solves and the round clock. Losing this mid-session resets the
    # scoreboard in front of the room, so it gets a real volume.
    {"apiVersion": "v1", "kind": "PersistentVolumeClaim",
     "metadata": {"name": "ctf-data", "namespace": ns},
     "spec": {"accessModes": ["ReadWriteOnce"], "resources": {"requests": {"storage": "1Gi"}}}},
    {"apiVersion": "apps/v1", "kind": "Deployment",
     "metadata": {"name": "ctf", "namespace": ns},
     "spec": {"replicas": 1, "strategy": {"type": "Recreate"},
              "selector": {"matchLabels": {"app": "ctf"}},
              "template": {
                  "metadata": {"labels": {"app": "ctf"},
                               "annotations": {"ctf/checksum": hashlib.sha256(
                                   open("${HERE}/ctf.py", "rb").read()).hexdigest()[:16]}},
                  "spec": {
                      "containers": [{
                          "name": "ctf", "image": "${IMAGE}",
                          "command": ["python3", "/app/ctf.py"], "env": envs,
                          "ports": [{"containerPort": 8080}],
                          "volumeMounts": [{"name": "app", "mountPath": "/app"},
                                           {"name": "data", "mountPath": "/data"}],
                          "readinessProbe": {"httpGet": {"path": "/healthz", "port": 8080}},
                          "resources": {"requests": {"cpu": "50m", "memory": "64Mi"},
                                        "limits": {"memory": "256Mi"}}}],
                      "volumes": [{"name": "app", "configMap": {"name": "ctf"}},
                                  {"name": "data", "persistentVolumeClaim": {"claimName": "ctf-data"}}]}}}},
    {"apiVersion": "v1", "kind": "Service",
     "metadata": {"name": "ctf", "namespace": ns},
     "spec": {"selector": {"app": "ctf"},
              "ports": [{"name": "http", "port": 80, "targetPort": 8080}]}},
]
with open(sys.argv[1], "w") as fh:
    fh.write("\n---\n".join(json.dumps(d, indent=2) for d in docs) + "\n")
PYEOF

run "kubectl apply -f '$STATE/ctf.yaml'"
run "kubectl -n '$NS' rollout status deploy/ctf --timeout=300s"

if [[ -n "${RESET_CTF-}" ]]; then
  warn "RESET_CTF=1 — forgetting every player and every score"
  run "kubectl -n '$NS' exec deploy/ctf -- rm -f /data/ctf.json"
  run "kubectl -n '$NS' rollout restart deploy/ctf"
  run "kubectl -n '$NS' rollout status deploy/ctf --timeout=300s"
fi

# ------------------------------------------------------------- verification
say ""
say "Checking the things that would be embarrassing in front of a room, not"
say "just that it is up."
trap cleanup_port_forwards EXIT
port_forward "$NS" svc/ctf 18080:80
B="http://127.0.0.1:18080"
wait_for "the app to answer" 120 "curl -sf -o /dev/null '$B/healthz'"

BAD=0
check() {  # check "<description>" <expected> <actual>
  if [[ "$2" == "$3" ]]; then printf '  %s%s✓%s %s\n' "$BOLD" "$GREEN" "$RESET" "$1"
  else printf '  %s%s✗%s %s (expected %s, got %s)\n' "$BOLD" "$RED" "$RESET" "$1" "$2" "$3"; BAD=1; fi
}
code() { curl -sS -o /dev/null -w '%{http_code}' --max-time 15 "$@" || echo 000; }

for P in / /board /admin /api/board; do check "page $P renders" 200 "$(code "$B$P")"; done
check "a bad email is refused"            400 "$(code -XPOST "$B/api/join" -d '{"email":"nope"}')"
check "answers need a player"             401 "$(code -XPOST "$B/api/submit" -d '{"flag":"volume","answer":"x"}')"
check "round control needs the admin key" 403 "$(code -XPOST "$B/api/admin/round" -d '{"key":"wrong","action":"finish"}')"
check "the kagent gateway refuses a stranger" 401 "$(code "$B/gw/auth")"
if (( BAD )); then
  fail "the CTF app is not behaving"
  note "kubectl -n $NS logs deploy/ctf --tail=40"
  exit 1
fi

printf '\n'
ok "The CTF app is running."
note "admin key: $ADMIN_KEY     (also in $ADMIN_FILE)"
if [[ -n "$PUB_URL" ]]; then
  note "players:   $PUB_URL            <- the QR code on your slide"
  note "projector: $PUB_URL/board"
  note "you:       $PUB_URL/admin"
  note "everything is in place — docs/RUNSHEET.md has the order of play"
else
  note "next:  make hub-08   (kagent), then hub-09 (public HTTPS addresses)"
fi
