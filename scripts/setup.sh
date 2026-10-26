#!/usr/bin/env bash
# Create .env, the distrobox and install Agent Canvas inside it.
#   scripts/setup.sh            create (keeps an existing box)
#   scripts/setup.sh --replace  recreate the box (box home and its data are kept)
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

replace=0
case "${1:-}" in
  --replace) replace=1 ;;
  "") ;;
  *) die "usage: $0 [--replace]" ;;
esac

require_cmds distrobox podman openssl envsubst ip curl

if [[ ! -f $ENV_FILE ]]; then
  log "Creating .env from .env.example"
  (umask 077 && cp "$REPO_DIR/.env.example" "$ENV_FILE")
fi
chmod 600 "$ENV_FILE"
for key in LOCAL_BACKEND_API_KEY OH_SECRET_KEY; do
  if grep -qE "^$key=$" "$ENV_FILE"; then
    sed -i "s|^$key=$|$key=$(openssl rand -hex 32)|" "$ENV_FILE"
    ok "generated $key"
  fi
done

load_env
require_bind_ip
PROJECTS_DIR="${PROJECTS_DIR:-$HOME/agent-projects}"
mkdir -p "$BOX_HOME" "$PROJECTS_DIR"

log "Rendering $INI_FILE"
mkdir -p "$(dirname "$INI_FILE")"
BOX_NAME="$BOX_NAME" BOX_IMAGE="$BOX_IMAGE" BOX_HOME="$BOX_HOME" PROJECTS_DIR="$PROJECTS_DIR" \
  BIND_IP="$BIND_IP" PORT="$PORT" \
  envsubst '${BOX_NAME} ${BOX_IMAGE} ${BOX_HOME} ${PROJECTS_DIR} ${BIND_IP} ${PORT}' \
  < "$REPO_DIR/distrobox.ini.tmpl" > "$INI_FILE"

if box_exists; then
  if (( replace )); then
    confirm "Recreate box '$BOX_NAME'? (box home $BOX_HOME is kept)" || die "aborted"
    "$REPO_DIR/scripts/stop.sh" >/dev/null 2>&1 || true
    distrobox assemble create --replace --file "$INI_FILE"
  else
    ok "box '$BOX_NAME' already exists (use --replace to recreate)"
  fi
else
  log "Creating box '$BOX_NAME' ($BOX_IMAGE)"
  distrobox assemble create --file "$INI_FILE"
fi

install_box_scripts
log "Provisioning inside the box (first enter runs the distrobox init, this can take minutes)"
box_exec bash "$BOX_LIBEXEC/provision.sh" "$AGENT_CANVAS_VERSION"

ok "done – start with: scripts/start.sh -d   →   $URL"
