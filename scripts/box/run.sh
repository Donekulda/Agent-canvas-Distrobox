#!/usr/bin/env bash
# Runs INSIDE the box: launch agent-canvas in public mode on the box-internal port 8000.
set -euo pipefail

set -a
# shellcheck disable=SC1091
. "$HOME/.config/agent-canvas-box/secrets.env"
set +a

args=(--public --port 8000)
[[ ${MODE:-full} == frontend-only ]] && args+=(--frontend-only)

export PATH="$HOME/.local/bin:$PATH"
# agent-server and automation need Python >= 3.12; without a pin uvx may pick an older managed one.
export UV_PYTHON="${UV_PYTHON:-3.12}"
# Pins for upstream dependency breakage, see constraints.txt.
export UV_CONSTRAINT="$(dirname "$(readlink -f "$0")")/constraints.txt"
exec agent-canvas "${args[@]}"
