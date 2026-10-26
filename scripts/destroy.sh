#!/usr/bin/env bash
# Remove the box.
#   scripts/destroy.sh               remove the container (box home with data is kept)
#   scripts/destroy.sh --purge-home  also delete the box home (conversations, settings, automations)
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

purge=0
case "${1:-}" in
  --purge-home) purge=1 ;;
  "") ;;
  *) die "usage: $0 [--purge-home]" ;;
esac

load_env

if box_exists; then
  confirm "Remove box '$BOX_NAME'?" || die "aborted"
  "$REPO_DIR/scripts/stop.sh" || true
  distrobox rm --force "$BOX_NAME"
  ok "box removed"
else
  ok "box '$BOX_NAME' does not exist"
fi
rm -f "$INI_FILE"

if (( purge )) && [[ -d $BOX_HOME ]]; then
  confirm "Delete box home $BOX_HOME with ALL Agent Canvas data?" || die "aborted (box home kept)"
  rm -rf -- "$BOX_HOME"
  ok "box home deleted"
fi
