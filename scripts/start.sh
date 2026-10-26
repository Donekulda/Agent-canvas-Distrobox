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
acquire_lock
require_bind_ip
box_exists || die "box '$BOX_NAME' does not exist – run scripts/setup.sh"
require_published_matches

# Exactly one Agent Canvas: refuse to run next to one started directly on the host.
host_pids="$(host_running_pids | tr '\n' ' ')"
[[ -z $host_pids ]] || die "Agent Canvas is running on the host outside the box (pid $host_pids) – remove it: scripts/host-cleanup.sh"
[[ -z $(host_installs) ]] || warn "Agent Canvas is also installed on the host – remove it: scripts/host-cleanup.sh"
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
  # running_pid now sees this instance, so the lock isn't needed while it runs (and stop.sh needs it).
  release_lock
  exec distrobox enter "$BOX_NAME" -- "$BOX_LIBEXEC/run.sh"
fi

box_exec bash -c 'setsid "$1" >"$2" 2>&1 </dev/null & echo $! >"$3"' _ \
  "$BOX_LIBEXEC/run.sh" "$LOG_FILE" "$PID_FILE" 9>&-
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
