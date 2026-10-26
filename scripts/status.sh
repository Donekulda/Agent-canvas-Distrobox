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
published="$(box_published)"
printf '%-14s %s\n' "published:" "${published:-nothing}"
[[ $published == "$BIND_IP:$PORT" ]] \
  || warn "box publishes '$published' but .env says $BIND_IP:$PORT – recreate the box: scripts/setup.sh --replace"
printf '%-14s %s\n' "mode:" "$MODE"
installed="$(installed_version)"
printf '%-14s %s\n' "installed:" "${installed:-nothing} (.env: $AGENT_CANVAS_VERSION)"
[[ $installed == "$AGENT_CANVAS_VERSION" ]] \
  || warn "box has '${installed:-nothing}' but .env says $AGENT_CANVAS_VERSION – scripts/upgrade.sh"
printf '%-14s %s\n' "launcher:" "$(launcher_installed && echo "$DESKTOP_FILE" || echo "none (scripts/install.sh --launcher)")"
printf '%-14s %s\n' "api key:" "$([[ -n ${LOCAL_BACKEND_API_KEY:-} ]] && echo set || echo MISSING)"

pid="$(running_pid)"
if [[ -z $pid ]]; then
  printf '%-14s %s\n' "agent-canvas:" "not running"
elif [[ -f $PID_FILE && $(<"$PID_FILE") == "$pid" ]]; then
  printf '%-14s %s\n' "agent-canvas:" "running in background (pid $pid in box)"
else
  printf '%-14s %s\n' "agent-canvas:" "running in foreground (pid $pid in box)"
fi

# Anything outside the box means more than one Agent Canvas (or a stray launcher).
host_issue=0
host_pids="$(host_running_pids | tr '\n' ' ')"
host_inst="$(host_installs | wc -l)"
host_state="$(host_state_dirs | tr '\n' ' ')"
printf '%-14s %s\n' "host running:" "${host_pids:-none}"
printf '%-14s %s\n' "host install:" "$( (( host_inst )) && echo "$host_inst found" || echo none)"
printf '%-14s %s\n' "host state:" "${host_state:-none}"
printf '%-14s %s\n' "box entry:" "$([[ -f $BOX_ENTRY_FILE ]] && echo "$BOX_ENTRY_FILE" || echo none)"
[[ -z $host_pids && $host_inst == 0 && -z $host_state && ! -f $BOX_ENTRY_FILE ]] || host_issue=1
(( ! host_issue )) || warn "Agent Canvas leftovers outside the box – remove them: scripts/host-cleanup.sh"

code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "$URL/" || true)"
printf '%-14s %s\n' "$URL:" "${code/000/unreachable}"
for other in $(ip -4 -o addr show | awk '{split($4,a,"/"); print a[1]}'); do
  [[ -n $other && $other != "$BIND_IP" ]] || continue
  c="$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "http://$other:$PORT/" || true)"
  printf '%-14s %s\n' "$other:$PORT:" "$([[ $c == 000 ]] && echo 'unreachable (expected)' || echo "REACHABLE ($c) – check for another listener")"
done
