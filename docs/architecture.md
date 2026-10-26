# Architecture

```
 browser on the host
        │  http://127.0.0.1:8000   (BIND_IP only; not LAN, not tailscale0)
        ▼
 ┌─ host (Bazzite) ─────────────────────────────────────────────────────────┐
 │  pasta (rootless podman)  --publish 127.0.0.1:8000:8000                  │
 │        │                                                                 │
 │  ┌─ distrobox "agent-canvas"  (own netns / ipc / pid) ────────────────┐  │
 │  │      ▼                                                             │  │
 │  │  ingress + static UI  :8000  (agent-canvas --public)               │  │
 │  │      ├── /api, /sockets, /server_info → agent-server  :18000       │  │
 │  │      ├── /api/automation              → automation    :18001       │  │
 │  │      └── /vscode                      → editor (agent-server port) │  │
 │  │                                                                    │  │
 │  │  HOME = ~/.local/share/distrobox-homes/agent-canvas                │  │
 │  │         ├── .local/bin/agent-canvas      (npm, not on the host)    │  │
 │  │         ├── .openhands/agent-canvas/     (conversations, settings) │  │
 │  │         └── .config/agent-canvas-box/    (secrets.env, pid, log)   │  │
 │  │  /projects = ~/agent-projects                                      │  │
 │  │  /run/host = host root (distrobox always mounts it!)               │  │
 │  └────────────────────────────────────────────────────────────────────┘  │
 └──────────────────────────────────────────────────────────────────────────┘
        │ outgoing traffic (pasta)
        ▼
 remote agent-server backends / LLM APIs
```

In `MODE=frontend-only` neither agent-server nor automation is started. The box then serves only the UI
and ingress, and all agent work runs on remote backends.

Key flow: `.env` → `start.sh` writes `secrets.env` (0600) → `box/run.sh` loads it into the environment →
`agent-canvas --public` reads `LOCAL_BACKEND_API_KEY` and `OH_SECRET_KEY`.
