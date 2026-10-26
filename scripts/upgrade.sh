#!/usr/bin/env bash
# Install another @openhands/agent-canvas version inside the box.
#   scripts/upgrade.sh           reinstall AGENT_CANVAS_VERSION from .env
#   scripts/upgrade.sh 1.17.0    install 1.17.0 and write it to .env
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

load_env
box_exists || die "box '$BOX_NAME' does not exist – run scripts/setup.sh"

if [[ -n ${1:-} ]]; then
  [[ $1 =~ ^[0-9]+\.[0-9]+\.[0-9]+([-.][0-9A-Za-z.]+)?$ ]] || die "not a version: $1"
  sed -i "s|^AGENT_CANVAS_VERSION=.*|AGENT_CANVAS_VERSION=$1|" "$ENV_FILE"
  AGENT_CANVAS_VERSION="$1"
fi

[[ -z $(running_pid) ]] || die "agent-canvas is running – scripts/stop.sh --keep-box first"
install_box_scripts
box_exec bash "$BOX_LIBEXEC/provision.sh" "$AGENT_CANVAS_VERSION"
ok "agent-canvas $AGENT_CANVAS_VERSION installed"
