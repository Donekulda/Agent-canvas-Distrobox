#!/usr/bin/env bash
# Interactive menu for all scripts: a dashboard (state, installed, to do) above the action list.
# Uses gum (ships with Bazzite) if available, else bash select. Texts: scripts/locale/*.sh,
# language: menu → Language (saved as MENU_LANG in .env).
#   ./menu.sh
#   MENU_PLAIN=1 ./menu.sh   force the plain bash select menu
#   NO_COLOR=1 ./menu.sh     no colours
source "$(dirname "${BASH_SOURCE[0]}")/scripts/lib.sh"
source "$REPO_DIR/scripts/i18n.sh"

[[ -f $ENV_FILE ]] && load_env
i18n_load "$(i18n_detect)"
[[ -t 0 && -t 1 ]] || die "$(t msg.no_tty)"
S="$REPO_DIR/scripts"
has_gum=0
[[ -z ${MENU_PLAIN:-} ]] && command -v gum >/dev/null && has_gum=1
use_color=1
[[ -z ${NO_COLOR:-} ]] || use_color=0
KEY_CLEAR_SECONDS=60

ACTIONS=(start open stop status log key shell upgrade recreate hostclean install launcher destroy refresh lang quit)

# choose HEADER SELECTED_ID HEIGHT ID… – shows the translated labels (menu.<id>), prints the chosen ID.
choose() {
  local header="$1" selected="$2" height="$3" id label=""
  shift 3
  local labels=()
  for id in "$@"; do labels+=("$(t "menu.$id")"); done
  if (( has_gum )); then
    local preselect=()
    [[ -z $selected ]] || preselect=(--selected "$(t "menu.$selected")")
    label="$(gum choose --header "$header" --height "$height" "${preselect[@]}" -- "${labels[@]}")" || return 1
  else
    local PS3
    PS3="$(t prompt.choice) "
    printf '%s\n' "$header" >&2
    select label in "${labels[@]}"; do
      [[ -n $label ]] && break
    done
    [[ -n $label ]] || return 1
  fi
  for id in "$@"; do
    [[ $(t "menu.$id") == "$label" ]] && { printf '%s\n' "$id"; return 0; }
  done
  return 1
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

pause() { read -r -p $'\n'"$(t prompt.back) " _ || true; }

# Run a script without letting its failure (die/exit) end the menu.
run() { "$@" || warn "$(t msg.failed "$?")"; }

# --- Dashboard -----------------------------------------------------------------------------------

declare -A GLYPH=([ok]="✓" [warn]="!" [err]="✗" [info]="·")
declare -A COLOR=([ok]="1;32" [warn]="1;33" [err]="1;31" [info]="2")

paint() {
  if (( use_color )); then printf '\033[%sm%s\033[0m' "$1" "$2"; else printf '%s' "$2"; fi
}

# row LEVEL LABEL VALUE – one dashboard line. Pads by characters (printf pads by bytes).
row() {
  local pad=$(( 13 - ${#2} ))
  (( pad > 0 )) || pad=1
  printf '%s %s%*s%s' "$(paint "${COLOR[$1]}" "${GLYPH[$1]}")" "$2" "$pad" "" "$3"
}

todo() { TODO+=("$(paint 1 "→") $2"); TODO_ACT+=("$1"); }

# Fill STATE, INSTALLED, TODO (+ TODO_ACT, PRESELECT). Read-only: inspects, never changes anything.
dashboard() {
  load_env
  STATE=() INSTALLED=() TODO=() TODO_ACT=() PRESELECT=""
  local exists=0 status="" image="" pid="" published="" installed code addr=1 pub_ok=1 ver_ok=1
  local -a host_pids host_inst host_state
  if box_exists; then
    exists=1
    IFS='|' read -r status image < <(podman container inspect -f '{{.State.Status}}|{{.ImageName}}' "$BOX_NAME" 2>/dev/null) || true
    pid="$(running_pid)"
    published="$(box_published)"
  fi
  installed="$(installed_version)"
  bind_ip_present || addr=0

  # State
  if (( ! exists )); then
    STATE+=("$(row err "$(t dash.box)" "$(t dash.missing)")")
  elif [[ $status == running ]]; then
    STATE+=("$(row ok "$(t dash.box)" "$(t dash.running)")")
  else
    STATE+=("$(row info "$(t dash.box)" "$(t dash.stopped "${status:-?}")")")
  fi
  if (( exists )); then
    if [[ -z $pid ]]; then
      STATE+=("$(row info "$(t dash.canvas)" "$(t dash.not_running)")")
    elif [[ -f $PID_FILE && $(<"$PID_FILE") == "$pid" ]]; then
      STATE+=("$(row ok "$(t dash.canvas)" "$(t dash.bg)")")
    else
      STATE+=("$(row ok "$(t dash.canvas)" "$(t dash.fg)")")
    fi
  fi
  if [[ -n $pid ]]; then
    code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 "$URL/" || true)"
    if [[ $code =~ ^[23] ]]; then
      STATE+=("$(row ok "$(t dash.url)" "$(t dash.reachable "$URL" "$code")")")
    else
      STATE+=("$(row warn "$(t dash.url)" "$(t dash.unreachable "$URL")")")
    fi
  else
    STATE+=("$(row info "$(t dash.url)" "$URL")")
  fi
  if (( exists )); then
    if [[ $published == "$BIND_IP:$PORT" ]]; then
      STATE+=("$(row ok "$(t dash.published)" "$(t dash.pub_ok "$published")")")
    else
      pub_ok=0
      STATE+=("$(row err "$(t dash.published)" "$(t dash.pub_bad "${published:--}" "$BIND_IP:$PORT")")")
    fi
  fi
  if (( addr )); then
    STATE+=("$(row ok "$(t dash.address)" "$(t dash.addr_ok "$BIND_IP")")")
  else
    STATE+=("$(row err "$(t dash.address)" "$(t dash.addr_bad "$BIND_IP")")")
  fi

  # Installed
  if [[ $installed == "$AGENT_CANVAS_VERSION" ]]; then
    INSTALLED+=("$(row ok "$(t dash.version)" "$installed")")
  elif [[ -z $installed ]]; then
    ver_ok=0
    INSTALLED+=("$(row "$( (( exists )) && echo err || echo info)" "$(t dash.version)" "$(t dash.ver_none "$AGENT_CANVAS_VERSION")")")
  else
    ver_ok=0
    INSTALLED+=("$(row warn "$(t dash.version)" "$(t dash.ver_bad "$installed" "$AGENT_CANVAS_VERSION")")")
  fi
  image="${image:-${BOX_IMAGE:--}}"
  INSTALLED+=("$(row info "$(t dash.image)" "${image##*/}")")
  INSTALLED+=("$(row info "$(t dash.projects)" "${PROJECTS_DIR:--} → /projects")")
  if launcher_installed; then
    INSTALLED+=("$(row ok "$(t dash.launcher)" "$(t dash.yes)")")
  else
    INSTALLED+=("$(row warn "$(t dash.launcher)" "$(t dash.no)")")
  fi
  mapfile -t host_pids < <(host_running_pids || true)
  mapfile -t host_inst < <(host_installs)
  mapfile -t host_state < <(host_state_dirs)
  local leftovers=$(( ${#host_pids[@]} + ${#host_inst[@]} + ${#host_state[@]} ))
  [[ ! -f $BOX_ENTRY_FILE ]] || leftovers=$(( leftovers + 1 ))
  if (( leftovers )); then
    INSTALLED+=("$(row warn "$(t dash.host)" "$(t dash.host_found "$leftovers")")")
  else
    INSTALLED+=("$(row ok "$(t dash.host)" "$(t dash.host_none)")")
  fi
  # Only whether the key is set – never its value.
  if [[ -n ${LOCAL_BACKEND_API_KEY:-} ]]; then
    INSTALLED+=("$(row ok "$(t dash.apikey)" "$(t dash.set)")")
  else
    INSTALLED+=("$(row err "$(t dash.apikey)" "$(t dash.unset)")")
  fi
  INSTALLED+=("$(row info "$(t dash.tools)" "gum $( (( has_gum )) && echo ✓ || echo ✗) · wl-copy $(command -v wl-copy >/dev/null && echo ✓ || echo ✗)")")

  # To do, most important first; the first one is preselected in the menu.
  (( exists )) || todo install "$(t todo.install)"
  (( addr )) || todo status "$(t todo.bind_ip "$BIND_IP")"
  if (( exists && ! pub_ok )); then todo recreate "$(t todo.recreate "${published:--}" "$BIND_IP:$PORT")"; fi
  if (( exists && ! ver_ok )); then todo upgrade "$(t todo.upgrade "$AGENT_CANVAS_VERSION")"; fi
  (( ! leftovers )) || todo hostclean "$(t todo.hostclean)"
  if (( exists )) && [[ -z ${LOCAL_BACKEND_API_KEY:-} ]]; then todo install "$(t todo.apikey)"; fi
  launcher_installed || todo launcher "$(t todo.launcher)"
  if (( exists )) && [[ -z $pid ]] && (( ${#TODO[@]} == 0 )); then todo start "$(t todo.start)"; fi
  if (( ${#TODO[@]} )); then
    PRESELECT="${TODO_ACT[0]}"
  else
    TODO+=("$(paint "${COLOR[ok]}" "${GLYPH[ok]}") $(t todo.none)")
    PRESELECT=open
  fi
}

# panel WIDTH TITLE LINE… – a bordered box with gum, a titled block without it.
panel() {
  local width="$1" title="$2"
  shift 2
  if (( has_gum )); then
    gum style --border rounded --border-foreground 8 --padding "0 1" --width "$width" "$(paint 1 "$title")" "$@"
  else
    printf '%s\n' "$(paint 1 "── $title ──")" "$@" ""
  fi
}

render() {
  local cols w
  cols="$(tput cols 2>/dev/null || echo 80)"
  if (( has_gum && cols >= 100 )); then
    # Same height side by side.
    while (( ${#STATE[@]} < ${#INSTALLED[@]} )); do STATE+=(""); done
    while (( ${#INSTALLED[@]} < ${#STATE[@]} )); do INSTALLED+=(""); done
    w=$(( (cols - 4) / 2 ))
    (( w <= 60 )) || w=60
    gum join --horizontal \
      "$(panel "$w" "$(t dash.title "$BOX_NAME" "$MODE")" "${STATE[@]}")" \
      "$(panel "$w" "$(t dash.installed)" "${INSTALLED[@]}")"
    panel $(( 2 * w + 2 )) "$(t dash.todo)" "${TODO[@]}"
  else
    w=$(( cols - 2 ))
    (( w <= 78 )) || w=78
    panel "$w" "$(t dash.title "$BOX_NAME" "$MODE")" "${STATE[@]}"
    panel "$w" "$(t dash.installed)" "${INSTALLED[@]}"
    panel "$w" "$(t dash.todo)" "${TODO[@]}"
  fi
}

# --- Actions -------------------------------------------------------------------------------------

copy_key() {
  load_env
  [[ -n ${LOCAL_BACKEND_API_KEY:-} ]] || { warn "$(t msg.key_empty)"; return 1; }
  if command -v wl-copy >/dev/null && [[ -n ${WAYLAND_DISPLAY:-} ]]; then
    # Never printed. --sensitive keeps clipboard managers (Klipper) from storing it in their history.
    # No --paste-once: Klipper reads every new entry at once and would use up the only paste.
    # The forked wl-copy and the clearing job outlive this call – they don't get the secrets in their env.
    local sensitive=() sum
    wl-copy --help 2>&1 | grep -q -- --sensitive && sensitive=(--sensitive)
    printf '%s' "$LOCAL_BACKEND_API_KEY" | env -u LOCAL_BACKEND_API_KEY -u OH_SECRET_KEY wl-copy "${sensitive[@]}"
    # Clear it after KEY_CLEAR_SECONDS, unless something else has been copied meanwhile.
    sum="$(printf '%s' "$LOCAL_BACKEND_API_KEY" | sha256sum)"
    (
      unset LOCAL_BACKEND_API_KEY OH_SECRET_KEY
      sleep "$KEY_CLEAR_SECONDS"
      [[ $(wl-paste -n 2>/dev/null | sha256sum) != "$sum" ]] || wl-copy --clear
    ) </dev/null >/dev/null 2>&1 &
    disown
    ok "$(t msg.key_copied "$KEY_CLEAR_SECONDS")"
  else
    warn "$(t msg.key_no_wl "$ENV_FILE")"
  fi
}

follow_log() {
  load_env
  [[ -f $LOG_FILE ]] || { warn "$(t msg.no_log "$LOG_FILE")"; return 0; }
  log "$(t msg.log_hint)"
  # tail in its own subshell: Ctrl+C ends tail, not the menu.
  ( trap - INT; tail -n 50 -f "$LOG_FILE" ) || true
}

choose_lang() {
  local id lang
  id="$(choose "$(t menu.lang_header)" "lang.$I18N_LANG" $(( ${#LANGS[@]} + 2 )) "${LANGS[@]/#/lang.}")" || return 0
  lang="${id#lang.}"
  valid_lang "$lang" || return 0
  i18n_load "$lang"
  # Under the lock: upgrade.sh/install.sh write .env too.
  ( acquire_lock && set_env MENU_LANG "$lang" ) 2>/dev/null || { warn "$(t msg.lang_not_saved)"; pause; }
}

if [[ ! -f $ENV_FILE ]]; then
  confirm "$(t prompt.not_installed)" || exit 1
  "$S/install.sh"
fi

trap 'printf "\n"' INT
while true; do
  clear 2>/dev/null || true
  dashboard
  screen="$(render)"
  printf '%s\n' "$screen"
  height=$(( $(tput lines 2>/dev/null || echo 40) - $(wc -l <<<"$screen") - 2 ))
  (( height >= 5 )) || height=5
  choice="$(choose "$(t menu.header)" "$PRESELECT" "$height" "${ACTIONS[@]}")" || break
  case "$choice" in
    start)     run "$S/launch.sh" ;;
    open)      xdg-open "$URL/" >/dev/null 2>&1 & continue ;;
    stop)      run "$S/stop.sh" ;;
    status)    run "$S/status.sh" ;;
    log)       follow_log; continue ;;
    key)       run copy_key ;;
    shell)     run distrobox enter "$BOX_NAME"; continue ;;
    upgrade)
      version="$(ask "$(t prompt.version "$AGENT_CANVAS_VERSION")")" || continue
      if [[ -n $version ]]; then run "$S/upgrade.sh" "$version"; else run "$S/upgrade.sh"; fi ;;
    recreate)  run "$S/setup.sh" --replace ;;
    hostclean) run "$S/host-cleanup.sh" ;;
    install)   run "$S/install.sh" ;;
    launcher)  run "$S/install.sh" --launcher ;;
    destroy)   run "$S/destroy.sh" ;;
    refresh)   continue ;;
    lang)      choose_lang; continue ;;
    quit|"")   break ;;
  esac
  pause
done
