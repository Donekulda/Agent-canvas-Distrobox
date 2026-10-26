#!/usr/bin/env bash
# Shared helpers for the host-side scripts. Source, don't execute.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$REPO_DIR/.env"

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
  [[ $MODE == full || $MODE == frontend-only ]] || die "MODE must be 'full' or 'frontend-only', got '$MODE'"

  # Paths are identical inside and outside the box (distrobox mounts BOX_HOME at the same path).
  BOX_LIBEXEC="$BOX_HOME/.local/libexec/agent-canvas-box"
  BOX_STATE="$BOX_HOME/.config/agent-canvas-box"
  PID_FILE="$BOX_STATE/agent-canvas.pid"
  LOG_FILE="$BOX_STATE/agent-canvas.log"
  SECRETS_FILE="$BOX_STATE/secrets.env"
  INI_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/distrobox/$BOX_NAME.ini"
  URL="http://$BIND_IP:$PORT"
}

# Publishing on an address the host doesn't have fails (e.g. after a DHCP change).
require_bind_ip() {
  ip -4 -o addr show | awk '{split($4, a, "/"); print a[1]}' | grep -qxF "$BIND_IP" \
    || die "BIND_IP $BIND_IP is not on any host interface (ip -4 addr). Fix BIND_IP in .env and recreate the box (scripts/setup.sh --replace)."
}

box_exists() { podman container exists "$BOX_NAME"; }

box_exec() { distrobox enter "$BOX_NAME" -- "$@"; }

# Copy the in-box scripts into the box home (the repo path isn't mounted inside the box).
install_box_scripts() {
  install -d -m 700 "$BOX_STATE"
  install -D -m 755 "$REPO_DIR"/scripts/box/*.sh -t "$BOX_LIBEXEC"
  install -D -m 644 "$REPO_DIR"/scripts/box/constraints.txt -t "$BOX_LIBEXEC"
}

# PID (inside the box's PID namespace) of a running agent-canvas, or nothing.
running_pid() {
  [[ -f $PID_FILE ]] || return 0
  local pid
  pid="$(<"$PID_FILE")"
  [[ $(podman container inspect -f '{{.State.Running}}' "$BOX_NAME" 2>/dev/null) == true ]] || return 0
  if podman exec "$BOX_NAME" kill -0 "$pid" 2>/dev/null; then
    echo "$pid"
  fi
}
