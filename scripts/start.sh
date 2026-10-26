#!/usr/bin/env bash
# Start Agent Canvas inside the box.
#   scripts/start.sh      foreground (Ctrl+C stops it)
#   scripts/start.sh -d   background, log in $BOX_HOME/.config/agent-canvas-box/agent-canvas.log
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

detach=0
case "${1:-}" in
  -d|--detach) detach=1 ;;
  "") ;;
  *) die "usage: $0 [-d]" ;;
esac

load_env
require_bind_ip
box_exists || die "box '$BOX_NAME' does not exist – run scripts/setup.sh"
[[ -n ${LOCAL_BACKEND_API_KEY:-} ]] || die "LOCAL_BACKEND_API_KEY is empty in .env (public mode requires it)"

install_box_scripts
# Secrets go through a 0600 file read by run.sh, never through argv (visible in ps).
(
  umask 077
  printf 'LOCAL_BACKEND_API_KEY=%q\nOH_SECRET_KEY=%q\nMODE=%q\n' \
    "$LOCAL_BACKEND_API_KEY" "${OH_SECRET_KEY:-}" "$MODE" > "$SECRETS_FILE"
)

# Starts the box if it is stopped.
box_exec true

pid="$(running_pid)"
[[ -z $pid ]] || die "already running (pid $pid in box) – $URL"

if (( ! detach )); then
  log "Agent Canvas ($MODE) → $URL  (UI asks for LOCAL_BACKEND_API_KEY from .env)"
  exec distrobox enter "$BOX_NAME" -- "$BOX_LIBEXEC/run.sh"
fi

box_exec bash -c 'setsid "$1" >"$2" 2>&1 </dev/null & echo $! >"$3"' _ \
  "$BOX_LIBEXEC/run.sh" "$LOG_FILE" "$PID_FILE"
log "started in background (pid $(<"$PID_FILE") in box), log: $LOG_FILE"

for _ in $(seq 60); do
  if curl -fs -o /dev/null --max-time 2 "$URL/"; then
    ok "Agent Canvas ($MODE) → $URL  (UI asks for LOCAL_BACKEND_API_KEY from .env)"
    exit 0
  fi
  [[ -n $(running_pid) ]] || die "agent-canvas exited – see $LOG_FILE"
  sleep 2
done
warn "$URL not answering yet (first start downloads agent-server via uvx) – check scripts/status.sh / $LOG_FILE"
