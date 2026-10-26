#!/usr/bin/env bash
# Desktop launcher (used by the app icon from scripts/install.sh).
#   scripts/launch.sh         start Agent Canvas in the background if needed, then open the UI
#   scripts/launch.sh --stop  stop Agent Canvas and the box
# Without a terminal, output goes to $BOX_HOME/.config/agent-canvas-box/launcher.log.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

stop=0
case "${1:-}" in
  --stop) stop=1 ;;
  "") ;;
  *) die "usage: $0 [--stop]" ;;
esac

# Never put secrets into notifications – they end up in the notification history.
notify() {
  command -v notify-send >/dev/null || return 0
  notify-send -a "Agent Canvas" -i agent-canvas-distrobox "$@" || true
}

load_env
if [[ ! -t 1 ]]; then
  install -d -m 700 "$BOX_STATE"
  (umask 077 && touch "$BOX_STATE/launcher.log")
  exec >>"$BOX_STATE/launcher.log" 2>&1
  printf '\n--- %s %s\n' "$(date -Is)" "${1:-start}"
fi

if (( stop )); then
  if "$REPO_DIR/scripts/stop.sh"; then
    notify "Agent Canvas stopped"
  else
    notify -u critical "Agent Canvas: stop failed" "See $BOX_STATE/launcher.log"
    exit 1
  fi
  exit 0
fi

if [[ -z $(running_pid) ]] && ! curl -fs -o /dev/null --max-time 2 "$URL/"; then
  notify "Agent Canvas is starting…" "The first start downloads the agent-server and can take minutes."
  if ! "$REPO_DIR/scripts/start.sh" -d; then
    notify -u critical "Agent Canvas failed to start" "See $BOX_STATE/launcher.log"
    exit 1
  fi
fi

xdg-open "$URL/"
