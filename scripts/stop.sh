#!/usr/bin/env bash
# Stop Agent Canvas and the box.
#   scripts/stop.sh             stop agent-canvas and the container
#   scripts/stop.sh --keep-box  stop only agent-canvas
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

keep_box=0
case "${1:-}" in
  --keep-box) keep_box=1 ;;
  "") ;;
  *) die "usage: $0 [--keep-box]" ;;
esac

load_env
box_exists || die "box '$BOX_NAME' does not exist"

pid="$(running_pid)"
if [[ -n $pid ]]; then
  log "Stopping agent-canvas (pid $pid in box)"
  # setsid made it a process-group leader: signal the whole group (agent-server, automation, ingress).
  podman exec "$BOX_NAME" kill -TERM -- "-$pid" 2>/dev/null || true
  for _ in $(seq 20); do
    podman exec "$BOX_NAME" kill -0 "$pid" 2>/dev/null || break
    sleep 1
  done
  podman exec "$BOX_NAME" kill -KILL -- "-$pid" 2>/dev/null || true
  ok "agent-canvas stopped"
else
  ok "agent-canvas not running (background instance)"
fi
rm -f "$PID_FILE"

if (( ! keep_box )); then
  distrobox stop --yes "$BOX_NAME" >/dev/null
  ok "box '$BOX_NAME' stopped"
fi
