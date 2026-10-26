#!/usr/bin/env bash
# Install everything: box + Agent Canvas (setup.sh) and a desktop launcher with an app icon.
#   scripts/install.sh              setup.sh + launcher
#   scripts/install.sh --launcher   only (re)install the launcher and icon (e.g. after moving the repo)
#   scripts/install.sh --uninstall  remove the launcher and icon (the box stays; see destroy.sh)
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

APP_ID=agent-canvas-distrobox
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
DESKTOP_FILE="$DATA_HOME/applications/$APP_ID.desktop"
ICON_DIR="$DATA_HOME/icons/hicolor"
ICON_FILE="$ICON_DIR/scalable/apps/$APP_ID.svg"

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

case "${1:-}" in
  "")
    "$REPO_DIR/scripts/setup.sh"
    install_launcher
    ok "find 'OpenHands Agent Canvas' in the app menu (or run scripts/launch.sh)"
    ;;
  --launcher) install_launcher ;;
  --uninstall) uninstall_launcher ;;
  *) die "usage: $0 [--launcher | --uninstall]" ;;
esac
