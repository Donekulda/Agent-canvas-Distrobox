#!/usr/bin/env bash
# Interactive menu for all scripts. Uses gum (ships with Bazzite) if available, else bash select.
#   ./menu.sh
#   MENU_PLAIN=1 ./menu.sh   force the plain bash select menu
source "$(dirname "${BASH_SOURCE[0]}")/scripts/lib.sh"

[[ -t 0 && -t 1 ]] || die "menu.sh needs a terminal"
S="$REPO_DIR/scripts"
has_gum=0
[[ -z ${MENU_PLAIN:-} ]] && command -v gum >/dev/null && has_gum=1

choose() {
  if (( has_gum )); then
    gum choose --header "$1" --height 20 -- "${@:2}"
  else
    local PS3="choice> " item
    printf '%s\n' "$1" >&2
    select item in "${@:2}"; do
      [[ -n $item ]] && { printf '%s\n' "$item"; return 0; }
    done
    return 1
  fi
}

ask() {
  if (( has_gum )); then
    gum input --placeholder "$1"
  else
    local reply
    read -r -p "$1: " reply
    printf '%s\n' "$reply"
  fi
}

pause() { read -r -p $'\nEnter = back to menu ' _ || true; }

# Run a script without letting its failure (die/exit) end the menu.
run() { "$@" || warn "failed (exit $?)"; }

header() {
  load_env
  local state
  if ! box_exists; then
    state="box missing – Install / setup"
  elif [[ -n $(running_pid) ]]; then
    state="running → $URL"
  else
    state="stopped ($URL)"
  fi
  if box_exists && [[ $(box_published) != "$BIND_IP:$PORT" ]]; then
    state+=" – ! box publishes $(box_published), .env changed: Recreate box"
  fi
  printf 'Agent Canvas (%s, %s) – %s' "$BOX_NAME" "$MODE" "$state"
}

copy_key() {
  load_env
  [[ -n ${LOCAL_BACKEND_API_KEY:-} ]] || { warn "LOCAL_BACKEND_API_KEY is empty – run setup"; return 1; }
  if command -v wl-copy >/dev/null && [[ -n ${WAYLAND_DISPLAY:-} ]]; then
    # Paste-once: the key disappears from the clipboard after the first paste. Never printed.
    printf '%s' "$LOCAL_BACKEND_API_KEY" | wl-copy --paste-once
    ok "API key copied – paste it once into the UI (clipboard is cleared after that)"
  else
    warn "no wl-copy/Wayland – show it yourself: grep ^LOCAL_BACKEND_API_KEY= $ENV_FILE | cut -d= -f2"
  fi
}

follow_log() {
  load_env
  [[ -f $LOG_FILE ]] || { warn "no log yet: $LOG_FILE"; return 0; }
  log "Ctrl+C returns to the menu"
  # tail in its own subshell: Ctrl+C ends tail, not the menu.
  ( trap - INT; tail -n 50 -f "$LOG_FILE" ) || true
}

items=(
  "Start + open UI"
  "Open UI"
  "Stop"
  "Status"
  "Follow log"
  "Copy API key"
  "Shell in box"
  "Upgrade Agent Canvas"
  "Recreate box"
  "Remove host install"
  "Install / setup"
  "Reinstall launcher icon"
  "Remove box"
  "Quit"
)

if [[ ! -f $ENV_FILE ]]; then
  confirm "Not installed yet (no .env). Run scripts/install.sh now?" || exit 1
  "$S/install.sh"
fi

trap 'printf "\n"' INT
while true; do
  clear 2>/dev/null || true
  choice="$(choose "$(header)" "${items[@]}")" || break
  case "$choice" in
    "Start + open UI")         run "$S/launch.sh" ;;
    "Open UI")                 load_env; xdg-open "$URL/" >/dev/null 2>&1 & continue ;;
    "Stop")                    run "$S/stop.sh" ;;
    "Status")                  run "$S/status.sh" ;;
    "Follow log")              follow_log; continue ;;
    "Copy API key")            run copy_key ;;
    "Shell in box")            load_env; run distrobox enter "$BOX_NAME"; continue ;;
    "Upgrade Agent Canvas")
      load_env
      version="$(ask "version (empty = reinstall $AGENT_CANVAS_VERSION)")" || continue
      if [[ -n $version ]]; then run "$S/upgrade.sh" "$version"; else run "$S/upgrade.sh"; fi ;;
    "Recreate box")            run "$S/setup.sh" --replace ;;
    "Remove host install")     run "$S/host-cleanup.sh" ;;
    "Install / setup")         run "$S/install.sh" ;;
    "Reinstall launcher icon") run "$S/install.sh" --launcher ;;
    "Remove box")              run "$S/destroy.sh" ;;
    "Quit"|"")                 break ;;
  esac
  pause
done
