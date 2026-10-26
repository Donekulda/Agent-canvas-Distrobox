#!/usr/bin/env bash
# Install everything: .env, host cleanup, box + Agent Canvas (setup.sh) and a desktop launcher with an icon.
# Run scripts/install.sh --help for the options.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

APP_ID=agent-canvas-distrobox
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
DESKTOP_FILE="$DATA_HOME/applications/$APP_ID.desktop"
ICON_DIR="$DATA_HOME/icons/hicolor"
ICON_FILE="$ICON_DIR/scalable/apps/$APP_ID.svg"

usage() {
  cat <<EOF
usage: $0 [options]
       $0 --launcher | --uninstall | --help

Configuration (written to .env; omitted options keep the current value):
  --bind-ip IP          host address the UI is published on (default 127.0.0.1)
  --port N              host port (default 8000)
  --version X.Y.Z       @openhands/agent-canvas version installed in the box
  --mode MODE           full | frontend-only
  --projects-dir DIR    absolute host path mounted as /projects in the box
  Changing --bind-ip, --port or --projects-dir on an existing box recreates it (asks first).

Agent Canvas installed directly on the host (npm/nvm/npx, ~/.openhands/agent-canvas):
  --remove-host-install remove it without asking
  --keep-host-install   leave it (not recommended: two instances, keys in the host \$HOME)
  (default: report it and ask)

Other:
  --launcher            only (re)install the app-menu launcher and icon (e.g. after moving the repo)
  --uninstall           remove the launcher and icon (the box stays; see scripts/destroy.sh)
  -h, --help            this help
EOF
}

refresh_caches() {
  command -v update-desktop-database >/dev/null && update-desktop-database -q "$DATA_HOME/applications" || true
  command -v gtk-update-icon-cache >/dev/null && gtk-update-icon-cache -q -t "$ICON_DIR" 2>/dev/null || true
}

install_launcher() {
  # Desktop entries split Exec on spaces and treat a few characters specially; refuse rather than escape.
  [[ $REPO_DIR =~ ^[A-Za-z0-9/._+-]+$ ]] || die "repo path '$REPO_DIR' has characters unsafe for a .desktop Exec line"
  local launch="$REPO_DIR/scripts/launch.sh"

  install -D -m 644 "$REPO_DIR/assets/$APP_ID.svg" "$ICON_FILE"
  # No secrets here: the entry only points at launch.sh, which reads .env itself.
  install -d "$(dirname "$DESKTOP_FILE")"
  cat > "$DESKTOP_FILE" <<EOF
[Desktop Entry]
Type=Application
Name=OpenHands Agent Canvas
GenericName=AI Agent Workspace
Comment=Start OpenHands Agent Canvas in its distrobox and open the UI
Exec=$launch
Icon=$APP_ID
Terminal=false
Categories=Development;
Keywords=OpenHands;Agent;Canvas;AI;
StartupNotify=false
Actions=stop;

[Desktop Action stop]
Name=Stop Agent Canvas
Exec=$launch --stop
EOF
  chmod 644 "$DESKTOP_FILE"
  if command -v desktop-file-validate >/dev/null; then
    desktop-file-validate "$DESKTOP_FILE" || die "invalid desktop entry $DESKTOP_FILE"
  fi
  refresh_caches
  ok "launcher installed: $DESKTOP_FILE"
}

uninstall_launcher() {
  rm -f "$DESKTOP_FILE" "$ICON_FILE"
  refresh_caches
  ok "launcher and icon removed (box untouched – scripts/destroy.sh removes it)"
}

action=install host=ask
declare -A conf=()
need_arg() { [[ $# -ge 2 && -n $2 ]] || die "$1 needs a value (see --help)"; }
while (( $# )); do
  case "$1" in
    --bind-ip)      need_arg "$@"; valid_ipv4 "$2" || die "not an IPv4 address: $2"; conf[BIND_IP]="$2"; shift ;;
    --port)         need_arg "$@"; valid_port "$2" || die "not a port: $2"; conf[PORT]="$2"; shift ;;
    --version)      need_arg "$@"; valid_version "$2" || die "not a version: $2"; conf[AGENT_CANVAS_VERSION]="$2"; shift ;;
    --mode)         need_arg "$@"; [[ $2 == full || $2 == frontend-only ]] || die "--mode must be full or frontend-only"
                    conf[MODE]="$2"; shift ;;
    --projects-dir) need_arg "$@"; [[ $2 =~ ^/[A-Za-z0-9/._+-]*$ ]] || die "--projects-dir must be an absolute path without spaces or special characters"
                    conf[PROJECTS_DIR]="$2"; shift ;;
    --remove-host-install) host=remove ;;
    --keep-host-install)   host=keep ;;
    --launcher)  action=launcher ;;
    --uninstall) action=uninstall ;;
    -h|--help)   usage; exit 0 ;;
    *) usage >&2; die "unknown option: $1" ;;
  esac
  shift
done

case "$action" in
  launcher)  install_launcher; exit 0 ;;
  uninstall) uninstall_launcher; exit 0 ;;
esac

require_cmds distrobox podman openssl envsubst ip curl flock
ensure_env
load_env

# Container properties (published address/port, mounts) need a recreated box.
replace=()
for key in "${!conf[@]}"; do
  [[ ${!key:-} == "${conf[$key]}" ]] && continue
  set_env "$key" "${conf[$key]}"
  ok "$key=${conf[$key]}"
  if [[ $key =~ ^(BIND_IP|PORT|PROJECTS_DIR)$ ]] && box_exists; then
    replace=(--replace)
  fi
done
load_env

case "$host" in
  remove) "$REPO_DIR/scripts/host-cleanup.sh" --yes ;;
  keep)   "$REPO_DIR/scripts/host-cleanup.sh" --check >/dev/null || warn "keeping Agent Canvas on the host (--keep-host-install)" ;;
  ask)    "$REPO_DIR/scripts/host-cleanup.sh" --check >/dev/null || "$REPO_DIR/scripts/host-cleanup.sh" \
            || warn "host install kept – remove it later with scripts/host-cleanup.sh" ;;
esac

"$REPO_DIR/scripts/setup.sh" "${replace[@]}"
install_launcher
ok "find 'OpenHands Agent Canvas' in the app menu, or run scripts/menu.sh"
