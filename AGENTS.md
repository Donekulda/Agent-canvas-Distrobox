# agent-canvas-distrobox

Host-side bash scripts that run OpenHands Agent Canvas in a distrobox published on a single IP (default 127.0.0.1).

## Security is paramount

Security is the most important property of this repo. It overrides convenience, speed and features:
when a change would weaken isolation or risk leaking a secret, don't make it — say so and propose a
safe alternative. If unsure whether something is safe, treat it as unsafe and ask.

- **Secrets never leave their files.** `.env`, `secrets.env`, `LOCAL_BACKEND_API_KEY`, `OH_SECRET_KEY`
  and any LLM/API keys are never printed, logged, committed, put into argv (visible in `ps`), URLs,
  notifications, `.desktop` files or docs. Pass them via 0600 files (`umask 077`), as `start.sh` does.
- **Before every commit** run `git status` and `git diff --cached` and check that nothing secret is
  staged; `git check-ignore -v <file>` must cover new secret/state files. Extend `.gitignore` rather than
  relying on care. Never `git add -A`/`git add .` blindly, never `--force` past `.gitignore`.
- **Network exposure stays minimal.** Default `BIND_IP=127.0.0.1`. Never publish on `0.0.0.0`, never drop
  `unshare_netns`, never publish the internal ports 18000/18001, never touch the host firewall.
- **Host stays untouched.** Don't mount the host `$HOME` (or more than `PROJECTS_DIR`) into the box, don't
  layer packages with rpm-ostree, don't install system-wide. User-level files only (`~/.local/…`).
- **Be honest about limits.** Distrobox is not a sandbox (`/run/host` is the host root); don't claim
  otherwise in docs or messages.
- **Destructive actions prompt.** `destroy.sh` and `setup.sh --replace` ask first; keep it that way for
  anything that deletes data or recreates the box.
- **Supply chain:** pin versions (`AGENT_CANVAS_VERSION`, `constraints.txt`); don't add dependencies or
  `curl | sh` installers without verifying them.

## Layout

All code, comments, docs and commit messages are in English.

- `menu.sh` and `scripts/*.sh` run on the host and source `scripts/lib.sh` (`load_env`, `require_bind_ip`, `running_pid`…).
- `scripts/install.sh` (options: `--help`) = `.env` flags + host cleanup + `setup.sh` + desktop launcher (`~/.local/share/applications/agent-canvas-distrobox.desktop`,
  icon from `assets/agent-canvas-distrobox.svg`). The launcher runs `scripts/launch.sh` (start -d + open UI, `--stop`).
- `menu.sh` (repo root) is an interactive front end (gum, bash `select` fallback); it only calls the other scripts.
- `scripts/host-cleanup.sh` removes Agent Canvas installed on the host; detection helpers (`host_installs`,
  `host_running_pids`, `host_state_dirs`) live in `lib.sh` and are used by `status.sh`/`start.sh`/`launch.sh`.
- `acquire_lock` (flock, fd 9) serialises start/stop/setup/upgrade/destroy; children inherit `AC_LOCK_HELD`.
  Long-lived children (agent-canvas, the browser) must not inherit fd 9 – `release_lock` or `9>&-` first.
- `.env` writes go through `set_env` (keeps 0600); values are validated first (`valid_*` in `lib.sh`).
- `scripts/box/*.sh` run INSIDE the box. The repo path isn't mounted there, so `install_box_scripts`
  copies them into `$BOX_HOME/.local/libexec/agent-canvas-box/` before each use.
- The box definition is `distrobox.ini.tmpl` → rendered by `setup.sh` (envsubst) into
  `~/.config/distrobox/$BOX_NAME.ini` → `distrobox assemble create`. Change container properties there.
  `entry=false` keeps distrobox from adding its own menu entry. `BIND_IP`/`PORT`/`PROJECTS_DIR` are fixed at
  create time; `require_published_matches` catches `.env` edits that need `setup.sh --replace`.
- Network isolation relies on `unshare_netns` + `--publish $BIND_IP:$PORT:8000`; agent-canvas itself
  binds 0.0.0.0/:: and has no host option.
- `scripts/box/run.sh` pins `UV_PYTHON=3.12` and `UV_CONSTRAINT=constraints.txt` (fastapi<0.155 for agent-server 1.44).
- Check: `bash -n menu.sh scripts/*.sh scripts/box/*.sh`, then `scripts/status.sh`.
