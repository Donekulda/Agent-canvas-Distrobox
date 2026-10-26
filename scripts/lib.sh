#!/usr/bin/env bash
# Shared helpers for the host-side scripts. Source, don't execute.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$REPO_DIR/.env"
LOCK_FILE="${XDG_RUNTIME_DIR:-/tmp}/agent-canvas-distrobox.lock"
APP_ID=agent-canvas-distrobox
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
# App-menu launcher written by scripts/install.sh.
DESKTOP_FILE="$DATA_HOME/applications/$APP_ID.desktop"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m ✓\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m !\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m ✗\033[0m %s\n' "$*" >&2; exit 1; }

confirm() {
  local reply
  read -r -p "$1 [y/N] " reply
  [[ $reply =~ ^[yYaA]$ ]]
}

require_cmds() {
  local cmd
  for cmd in "$@"; do
    command -v "$cmd" >/dev/null || die "missing command: $cmd"
  done
}

valid_version() { [[ $1 =~ ^[0-9]+\.[0-9]+\.[0-9]+([-.][0-9A-Za-z.]+)?$ ]]; }
valid_port()    { [[ $1 =~ ^[0-9]{1,5}$ ]] && (( $1 >= 1 && $1 <= 65535 )); }
valid_lang()    { [[ $1 =~ ^(en|cs)$ ]]; }
valid_ipv4() {
  local IFS=. octet
  [[ $1 =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || return 1
  for octet in $1; do (( octet <= 255 )) || return 1; done
}

# Create .env from the template and generate missing keys. .env stays 0600.
ensure_env() {
  if [[ ! -f $ENV_FILE ]]; then
    log "Creating .env from .env.example"
    (umask 077 && cp "$REPO_DIR/.env.example" "$ENV_FILE")
  fi
  chmod 600 "$ENV_FILE"
  local key
  for key in LOCAL_BACKEND_API_KEY OH_SECRET_KEY; do
    if grep -qE "^$key=$" "$ENV_FILE"; then
      sed -i "s|^$key=$|$key=$(openssl rand -hex 32)|" "$ENV_FILE"
      ok "generated $key"
    fi
  done
}

# Set KEY=VALUE in .env (replace or append). Callers validate VALUE.
set_env() {
  local key="$1" value="$2" tmp
  [[ $value != *[$'\n'\\]* ]] || die "invalid value for $key"
  tmp="$(mktemp "$ENV_FILE.XXXXXX")" # 0600, gitignored (.env.*)
  awk -v k="$key" -v v="$value" '
    index($0, k "=") == 1 { print k "=" v; done = 1; next }
    { print }
    END { if (!done) print k "=" v }' "$ENV_FILE" > "$tmp"
  mv -f "$tmp" "$ENV_FILE"
}

load_env() {
  [[ -f $ENV_FILE ]] || die "no .env – run scripts/setup.sh first"
  set -a
  # shellcheck disable=SC1090
  . "$ENV_FILE"
  set +a
  : "${BOX_NAME:?BOX_NAME not set in .env}"
  : "${BIND_IP:?BIND_IP not set in .env}"
  : "${BOX_HOME:?BOX_HOME not set in .env}"
  PORT="${PORT:-8000}"
  MODE="${MODE:-full}"
  MENU_LANG="${MENU_LANG:-}"
  [[ $MODE == full || $MODE == frontend-only ]] || die "MODE must be 'full' or 'frontend-only', got '$MODE'"

  # Paths are identical inside and outside the box (distrobox mounts BOX_HOME at the same path).
  BOX_LIBEXEC="$BOX_HOME/.local/libexec/agent-canvas-box"
  BOX_STATE="$BOX_HOME/.config/agent-canvas-box"
  PID_FILE="$BOX_STATE/agent-canvas.pid"
  LOG_FILE="$BOX_STATE/agent-canvas.log"
  SECRETS_FILE="$BOX_STATE/secrets.env"
  INI_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/distrobox/$BOX_NAME.ini"
  # The .desktop file distrobox generates for a box (we disable it with entry=false).
  BOX_ENTRY_FILE="${XDG_DATA_HOME:-$HOME/.local/share}/applications/$BOX_NAME.desktop"
  URL="http://$BIND_IP:$PORT"
}

# One start/stop/setup at a time (double-clicked icon, menu + terminal…). Child scripts inherit
# AC_LOCK_HELD and skip it. Long-lived children (agent-canvas, browser) must not inherit fd 9:
# call release_lock before exec'ing them, or they would hold the lock forever.
acquire_lock() {
  [[ ${AC_LOCK_HELD:-} == 1 ]] && return 0
  exec 9>>"$LOCK_FILE"
  flock -n 9 || die "another start/stop/setup of Agent Canvas is in progress – try again in a moment"
  export AC_LOCK_HELD=1
}
release_lock() { exec 9>&-; unset AC_LOCK_HELD; }

# Publishing on an address the host doesn't have fails (e.g. after a DHCP change).
bind_ip_present() {
  ip -4 -o addr show | awk '{split($4, a, "/"); print a[1]}' | grep -qxF "$BIND_IP"
}
require_bind_ip() {
  bind_ip_present \
    || die "BIND_IP $BIND_IP is not on any host interface (ip -4 addr). Fix BIND_IP in .env and recreate the box (scripts/setup.sh --replace)."
}

box_exists() { podman container exists "$BOX_NAME"; }
box_running() { [[ $(podman container inspect -f '{{.State.Running}}' "$BOX_NAME" 2>/dev/null) == true ]]; }

# Host address:port the box actually publishes (fixed at create time; .env edits need --replace).
box_published() {
  podman container inspect -f \
    '{{range $p, $b := .HostConfig.PortBindings}}{{range $b}}{{.HostIP}}:{{.HostPort}} {{end}}{{end}}' \
    "$BOX_NAME" 2>/dev/null | xargs
}
require_published_matches() {
  local published
  published="$(box_published)"
  [[ $published == "$BIND_IP:$PORT" ]] \
    || die "box publishes '$published' but .env says $BIND_IP:$PORT – recreate the box: scripts/setup.sh --replace"
}

# agent-canvas version installed in the box, or nothing. Read on the host: BOX_HOME is a host path.
installed_version() {
  local pkg="$BOX_HOME/.local/lib/node_modules/@openhands/agent-canvas/package.json"
  [[ -f $pkg ]] || return 0
  sed -n 's/^  "version": *"\([^"]*\)".*/\1/p' "$pkg" | head -n 1
}

launcher_installed() { [[ -f $DESKTOP_FILE ]]; }

# Entering may start the container: its conmon would keep an inherited fd 9 (and the lock) open
# for as long as the box runs, so the box never gets the lock fd.
box_exec() { distrobox enter "$BOX_NAME" -- "$@" 9>&-; }

# Copy the in-box scripts into the box home (the repo path isn't mounted inside the box).
install_box_scripts() {
  install -d -m 700 "$BOX_STATE"
  install -D -m 755 "$REPO_DIR"/scripts/box/*.sh -t "$BOX_LIBEXEC"
  install -D -m 644 "$REPO_DIR"/scripts/box/constraints.txt -t "$BOX_LIBEXEC"
}

# PID (inside the box's PID namespace) of a running agent-canvas, or nothing.
# Covers the background instance (pid file) and a foreground one (scripts/start.sh without -d).
running_pid() {
  box_running || return 0
  local pid
  if [[ -f $PID_FILE ]]; then
    pid="$(<"$PID_FILE")"
    if podman exec "$BOX_NAME" kill -0 "$pid" 2>/dev/null; then
      echo "$pid"
      return 0
    fi
  fi
  podman exec "$BOX_NAME" pgrep -o -f 'bin/agent-canvas --public' 2>/dev/null || true
}

# --- Agent Canvas installed directly on the host (outside the box) ---------------------------

# Host state dirs of a host install. Only these subdirs: ~/.openhands may belong to other tools.
HOST_STATE_DIRS=("$HOME/.openhands/agent-canvas" "$HOME/.openhands/automation")

# Module dirs of host installs. Globs instead of PATH: nvm isn't loaded in a desktop session.
host_installs() {
  local p
  for p in "$HOME"/.nvm/versions/node/*/lib/node_modules/@openhands/agent-canvas \
           "$HOME"/.local/lib/node_modules/@openhands/agent-canvas \
           "$HOME"/.npm/_npx/*/node_modules/@openhands/agent-canvas \
           /usr/local/lib/node_modules/@openhands/agent-canvas \
           /usr/lib/node_modules/@openhands/agent-canvas; do
    [[ -d $p ]] && echo "$p"
  done
  return 0
}

# Host PIDs of agent-canvas node processes that are NOT in the box (box processes live in a
# libpod cgroup). Only node: shells, editors or podman whose args mention agent-canvas don't count.
host_running_pids() {
  local pid
  for pid in $(pgrep -u "$(id -u)" -f '(bin/agent-canvas|@openhands/agent-canvas)' || true); do
    [[ $(cat "/proc/$pid/comm" 2>/dev/null) == node ]] || continue
    grep -q libpod "/proc/$pid/cgroup" 2>/dev/null && continue
    echo "$pid"
  done
}

host_state_dirs() {
  local d
  for d in "${HOST_STATE_DIRS[@]}"; do
    [[ -e $d ]] && echo "$d"
  done
  return 0
}
