#!/usr/bin/env bash
# Runs INSIDE the box: system packages + @openhands/agent-canvas into ~/.local (box home).
set -euo pipefail

version="${1:?usage: provision.sh <agent-canvas-version>}"

sudo dnf install -y --setopt=install_weak_deps=False nodejs npm uv git

# agent-canvas requires node >= 22.12
node -e '
  const [maj, min] = process.versions.node.split(".").map(Number);
  if (maj < 22 || (maj === 22 && min < 12)) {
    console.error(`node ${process.versions.node} < 22.12`); process.exit(1);
  }'

# agent-server/automation need Python >= 3.12 (run.sh pins UV_PYTHON=3.12). Fedora's uv has
# python-downloads=manual, so install the managed interpreter explicitly (into the box home).
uv python install 3.12

npm config set prefix "$HOME/.local"
npm install -g "@openhands/agent-canvas@$version"
"$HOME/.local/bin/agent-canvas" --version
