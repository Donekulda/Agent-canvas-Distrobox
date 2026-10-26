# agent-canvas-distrobox

[OpenHands Agent Canvas](https://github.com/OpenHands/OpenHands) (`@openhands/agent-canvas`) in an isolated
distrobox on Bazzite / Fedora Atomic, reachable **on a single address only**. The default is a local UI at
`http://127.0.0.1:8000`. For LAN access set `BIND_IP` to the host's IP, e.g. `192.168.200.48`.

- own network namespace (podman + pasta); only the ingress is published, and only on `BIND_IP`
- own box home: the host `$HOME` is not mounted into the box, only `PROJECTS_DIR` as `/projects`
- `--public` mode: the UI asks for an API key (`LOCAL_BACKEND_API_KEY` from `.env`)
- manual start/stop scripts, no changes to the host (nothing layered, no firewall changes)

## Quick start

```bash
scripts/install.sh      # .env + keys, host cleanup, box, "OpenHands Agent Canvas" icon in the app menu
./menu.sh               # interactive menu for everything below
```

The icon starts Agent Canvas in the background (if it isn't running) and opens the UI in the browser.
Right-click → *Stop Agent Canvas* stops it. Launcher log: `$BOX_HOME/.config/agent-canvas-box/launcher.log`.
Clicking it again while it is starting only shows a notification – a lock allows one start/stop at a time.

### install.sh options

| Option | Effect |
|---|---|
| `--bind-ip IP` | host address the UI is published on (written to `.env`) |
| `--port N` | host port |
| `--version X.Y.Z` | `@openhands/agent-canvas` version in the box |
| `--mode full\|frontend-only` | see `MODE` below |
| `--projects-dir DIR` | absolute host path mounted as `/projects` |
| `--remove-host-install` | remove Agent Canvas installed directly on the host without asking |
| `--keep-host-install` | leave it (not recommended) |
| `--launcher` | only (re)install the icon, e.g. after moving the repo |
| `--uninstall` | remove the icon (the box stays) |

Changing `--bind-ip`, `--port` or `--projects-dir` on an existing box recreates it (asks first; data is kept).
Example: `scripts/install.sh --bind-ip 192.168.200.48 --port 8002 --remove-host-install`.

### Menu

`./menu.sh` opens with a dashboard:

- **State** – box running/stopped, agent-canvas in background/foreground, URL reachability, the published
  address vs `.env`, whether `BIND_IP` exists on a host interface;
- **Installed** – agent-canvas version in the box vs `AGENT_CANVAS_VERSION`, image, projects folder,
  launcher icon, leftovers on the host, API key set/missing (never the value), `gum`/`wl-copy`;
- **To do** – what to fix next, each naming the menu action; the first one is preselected.

Actions: start + open UI, open UI, stop, status, follow log, copy API key (to the Wayland clipboard
marked sensitive so Klipper keeps it out of its history, cleared after 60 s, never printed), shell in the box, upgrade, recreate box, host cleanup, install, reinstall icon,
remove box, refresh and language. It uses `gum` (ships with Bazzite) and falls back to a plain numbered
menu (`MENU_PLAIN=1` forces that, `NO_COLOR=1` drops colours).

The menu speaks English and Czech. **Language / Jazyk** saves the choice as `MENU_LANG=en|cs` in `.env`;
empty means it follows the system locale (`cs_*` → Czech). The scripts' own output stays English.

Manually:

```bash
scripts/setup.sh        # .env + keys, box, agent-canvas installed inside
scripts/launch.sh       # start in background + open the UI (same as the icon)
scripts/start.sh -d     # start in background (without -d it runs in the foreground)
scripts/status.sh       # state, published port, reachability
scripts/stop.sh         # stop agent-canvas + the box (--keep-box leaves the box running)
```

Then open `http://127.0.0.1:8000` and paste `LOCAL_BACKEND_API_KEY`:

```bash
grep ^LOCAL_BACKEND_API_KEY= .env | cut -d= -f2
```

More commands:

| Script | What it does |
|---|---|
| `scripts/host-cleanup.sh [--check]` | removes Agent Canvas installed on the host (see below) |
| `scripts/setup.sh --replace` | recreates the box (box home and data are kept), e.g. after changing `BIND_IP` |
| `scripts/upgrade.sh [version]` | installs another `@openhands/agent-canvas` version (and writes it to `.env`) |
| `scripts/destroy.sh [--purge-home]` | removes the box, with `--purge-home` also all data |

## Configuration

Everything is in `.env` (template `.env.example`; `.env` is gitignored and `chmod 600`):

| Variable | Default | Meaning |
|---|---|---|
| `BIND_IP` | `127.0.0.1` | the only host address the UI is published on (`127.0.0.1` = local only) |
| `PORT` | `8000` | host port (always 8000 inside the box) |
| `MODE` | `full` | `full` = UI + local agent-server + automation; `frontend-only` = UI only, for remote backends |
| `BOX_HOME` | `~/.local/share/distrobox-homes/agent-canvas` | box home (Agent Canvas state: `~/.openhands/…`) |
| `PROJECTS_DIR` | `~/agent-projects` | `/projects` inside the box |
| `AGENT_CANVAS_VERSION` | `1.16.0` | npm version |

Changes to `BIND_IP`, `PORT`, `PROJECTS_DIR` or `BOX_IMAGE` take effect only after `scripts/setup.sh --replace`,
because they are container properties. `MODE` and the keys are read on every `start.sh`.

The declarative box definition is rendered to `~/.config/distrobox/agent-canvas.ini` (from the
`distrobox.ini.tmpl` template).

## Why a separate network namespace

The `agent-canvas` launcher has no bind-address option. agent-server (18000) and automation (18001)
are started with `--host 0.0.0.0` and the ingress listens on `::`. In a regular distrobox (sharing the
host network) everything would listen on all interfaces, Tailscale included. So the box runs with
`--unshare-netns` and podman publishes only `BIND_IP:PORT → 8000`. Ports 18000 and 18001 stay inside.
Details in [docs/architecture.md](docs/architecture.md).

Remote backends (Settings → Backends) are reachable from the box as usual; outgoing traffic works through pasta.

## Security: what this isolates and what it doesn't

- **Distrobox is not a sandbox.** Distrobox always mounts the host root at `/run/host`. A process in the
  box can therefore technically read (and, as your user, write) host files. The separate home prevents
  *casual* access to the host `$HOME` (dotfiles, `~/.ssh`, tokens), but does not protect against a
  deliberately malicious agent.
- The local agent (`MODE=full`) runs unsandboxed as your user. For truly isolated agent work use
  remote or Docker backends, or `MODE=frontend-only`.
- The API key lives in `.env` (0600) and in `$BOX_HOME/.config/agent-canvas-box/secrets.env` (0600). It never
  reaches the command line (`ps`).
- With `BIND_IP=127.0.0.1` the UI is not reachable from other machines at all. If you put it on a LAN IP:
  firewalld (FedoraWorkstation zone) on Bazzite allows 1025–65535/tcp, so the whole LAN will see the UI and
  only the key protects it.

## Agent Canvas on the host

Only the box instance should exist. `scripts/status.sh` reports leftovers outside the box, `start.sh` and the
icon refuse to start while a host instance runs, and `scripts/host-cleanup.sh` removes them (after one prompt):

- running host instances (`node …/agent-canvas`, outside the box's cgroup)
- global installs in nvm (`~/.nvm/versions/node/*`), `~/.local` and the npx cache (`~/.npm/_npx`)
- host state with its keys: `~/.openhands/agent-canvas`, `~/.openhands/automation` (deleted, not backed up)
- the menu entry distrobox generates for the box (terminal + a "Remove" action); new boxes get `entry=false`

`scripts/install.sh` runs the check and asks; `--remove-host-install` / `--keep-host-install` decide upfront.
The box state (`$BOX_HOME/.openhands/agent-canvas`) is never touched.

## Troubleshooting

- `box publishes '127.0.0.1:8000' but .env says …`: `BIND_IP`/`PORT` in `.env` were edited after the box was
  created. Recreate it: `scripts/setup.sh --replace` (or menu → Recreate box).
- `another start/stop/setup of Agent Canvas is in progress`: wait for the other run to finish.
- `BIND_IP … is not on any host interface`: the IP changed (DHCP). Fix `.env` and run `scripts/setup.sh --replace`,
  or set up a DHCP reservation.
- The first start is slow: `uvx` downloads `openhands-agent-server` (about 200 MB). Follow it with
  `tail -f ~/.local/share/distrobox-homes/agent-canvas/.config/agent-canvas-box/agent-canvas.log`.
- Shell in the box: `distrobox enter agent-canvas`.
- `No interpreter found for Python 3.12`: Fedora's `uv` doesn't download Python by itself. So `provision.sh`
  runs `uv python install 3.12` and `run.sh` sets `UV_PYTHON=3.12`.
- `Query() got an unexpected keyword argument 'lte'`: agent-server 1.44.0 doesn't work with FastAPI ≥ 0.155.
  The pin is in `scripts/box/constraints.txt` (`UV_CONSTRAINT`). Once Agent Canvas moves to a newer
  agent-server (≥ 1.49), remove the pin.
