#!/usr/bin/env bash
# Show box state, published port and reachability.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

load_env
printf '%-14s %s\n' "box:" "$BOX_NAME"
if ! box_exists; then
  printf '%-14s %s\n' "state:" "does not exist (scripts/setup.sh)"
  exit 1
fi
printf '%-14s %s\n' "state:" "$(podman container inspect -f '{{.State.Status}}' "$BOX_NAME")"
printf '%-14s %s\n' "published:" "$(podman port "$BOX_NAME" 2>/dev/null | tr '\n' ' ' || true)"
printf '%-14s %s\n' "mode:" "$MODE"
printf '%-14s %s\n' "api key:" "$([[ -n ${LOCAL_BACKEND_API_KEY:-} ]] && echo set || echo MISSING)"

pid="$(running_pid)"
if [[ -n $pid ]]; then
  printf '%-14s %s\n' "agent-canvas:" "running (pid $pid in box)"
else
  printf '%-14s %s\n' "agent-canvas:" "not running in background"
fi

code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "$URL/" || true)"
printf '%-14s %s\n' "$URL:" "${code/000/unreachable}"
for other in $(ip -4 -o addr show | awk '{split($4,a,"/"); print a[1]}'); do
  [[ -n $other && $other != "$BIND_IP" ]] || continue
  c="$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "http://$other:$PORT/" || true)"
  printf '%-14s %s\n' "$other:$PORT:" "$([[ $c == 000 ]] && echo 'unreachable (expected)' || echo "REACHABLE ($c) – check for another listener")"
done
