# Hermes Agent

[Hermes Agent](https://github.com/NousResearch/hermes-agent) (Nous Research) — an
always-on agent that runs as a gateway against chat platforms, with a web
dashboard, a skill tree it edits itself, and a persistent memory store.

Restored from a native install on the `hermes` box
(`hermes-backup-2026-08-07-150039.zip`), not set up from scratch.

## Layout

| | |
|---|---|
| Image | `nousresearch/hermes-agent` (Docker Hub, multi-arch) |
| Dashboard | `https://hermes.calzone.zone` |
| Data | `/docker-data/hermes-agent` → `/opt/data` |
| Chat platform | Discord (`zBreezyyy / #hermes`) |
| MCP | MCPJungle at `https://mcp.calzone.zone/mcp` |

`/opt/data` is the single source of truth — `config.yaml`, `.env`, `SOUL.md`,
`skills/`, `memories/`, `sessions/`, `cron/`, `hooks/`, `logs/`. The image
itself is stateless; upgrades are a tag bump. Because it's a bind mount under
`/docker-data`, Backrest sweeps it with no extra configuration.

## Why this diverges from upstream's compose

Upstream's `docker-compose.yml` uses `build: .` and `network_mode: host`, with
the dashboard as a second container. Neither applies here:

- The image is published, so there's nothing to build.
- Host networking exists only to give a *separate* dashboard container a shared
  PID namespace for its gateway-liveness probe. `HERMES_DASHBOARD=1` runs both
  under one s6 supervision tree in a single container, so bridge + `proxy`
  works and Traefik routes to it like anything else.

## Dashboard auth

The dashboard reads and writes `.env` and exposes `PUT /api/env` — it is a
credential surface, not just a viewer.

Since Nous' June 2026 hardening, **a non-loopback bind fails closed**: if no
`DashboardAuthProvider` is registered, the dashboard refuses to start.
`HERMES_DASHBOARD_INSECURE` is a deprecated no-op that no longer opens it.
(The hardening followed a campaign where scanners found exposed dashboards and
drove the agents into planting SSH-key backdoors.)

That means Traefik's `pocket-id-auth@file` alone would *not* be enough — the
container would never come up. Hermes ships a `self_hosted` OIDC provider, so
it authenticates against pocket-id directly. Same SSO as everything else, one
login instead of two, and the edge middleware is redundant.

### DNS: the hostname collides with a real machine

`hermes.calzone.zone` resolves **differently depending on which resolver you
ask**, because the GPU box is itself named `hermes`:

| Resolver | Answer |
|---|---|
| AdGuard (`192.168.99.5`) — normal clients | `docker-01.calzone.zone` → `192.168.99.41` ✓ |
| UDM (`192.168.99.1`) — what docker01 itself uses | `192.168.1.43` (the GPU box) ✗ |

adguard-sync created the correct rewrite automatically, so browsers on the
LAN reach the dashboard fine. But docker01's own `resolvectl` points at the
UDM, not AdGuard, and the UDM answers with the physical host.

Nothing in this stack resolves its own hostname, so it works today. It is
still a latent trap — renaming the router to `hermes-agent.calzone.zone`
(matching the container and stack name) would remove the ambiguity. That
means changing the Traefik rule, `HERMES_DASHBOARD_PUBLIC_URL`, and the
pocket-id client's callback URL together.

### One-time pocket-id client

Create in pocket-id at `https://auth.calzone.zone`:

| Field | Value |
|---|---|
| Client ID | `hermes-dashboard` |
| Type | **Public** (PKCE / S256) — confidential clients with a secret are not supported |
| Callback URL | `https://hermes.calzone.zone/auth/callback` |
| Scopes | `openid profile email` |

Verify the gate is live once it's up:

```bash
curl -s https://hermes.calzone.zone/api/status | jq '.auth_required, .auth_providers'
# true
# ["self-hosted"]
```

## Model endpoint

**The one thing the backup does not carry.** `auth.json` is empty
(`active_provider: None`) and `.env` has no provider key — the model is a
*custom provider*, so the endpoint *is* the credential. As restored:

```yaml
model:
  provider: "custom:Local (localhost:8020)"
  base_url: http://localhost:8020/v1
  default:  /models/qwen3.6-27b-gguf/unsloth-mtp-q4km/Qwen3.6-27B-Q4_K_M.gguf
```

`localhost:8020` was the RTX 3090 box (`hermes`, `192.168.1.43`, Tailscale
`100.123.167.70`). On docker01 that resolves to the container itself, and
docker01 has no GPU and ~8 GB free. Only the host changes — the server is back
up and the model ID is byte-identical to the backup's:

```yaml
model:
  provider: "custom:Local (hermes:8020)"
  base_url: http://100.123.167.70:8020/v1
  default:  /models/qwen3.6-27b-gguf/unsloth-mtp-q4km/Qwen3.6-27B-Q4_K_M.gguf
```

Addressed over **Tailscale**, not the LAN IP (`192.168.1.43`, which also
works). docker01 and the GPU box sit on different subnets, so the LAN path
depends on inter-VLAN routing staying as it is; the Tailscale address does not,
and the traffic is encrypted in transit — this endpoint has no auth of its own,
so anything that can reach port 8020 can use the model.

**It is `http`, not `https`.** Port 8020 has no TLS listener; https connections
time out on both addresses. Verified from docker01 over the Tailscale address:
`/v1/models` returns the 27B, a chat completion round-trips, and function
calling returns well-formed `tool_calls` with `finish_reason: tool_calls` in
~0.5 s. That last check matters — Hermes is tool-call-driven, and `/v1/models`
advertises only `completion` in its `capabilities` array.

Inference lives on a box this repo doesn't manage, so the agent is only as
available as that server. Nothing here restarts it.

### Not used: ac-ollama

`hermes` also runs `ac-ollama` (AzerothCore stack,
`~/wow-server/azerothcore-wotlk/docker-compose.override.yml`). Deliberately not
used: it publishes no host port, and it is tuned for `mod-llm-chatter` with
`OLLAMA_CONTEXT_LENGTH=4096` (Hermes' skills prompt snapshot alone is 42 KB)
and `OLLAMA_MAX_LOADED_MODELS=1`, so it and the agent would evict each other's
model. Its own comment — *"safe here since this GPU has no other tenant"* — is
the assumption a second tenant would break. It holds only `qwen3:8b` and
`gemma4:12b`; the 27B is served separately on 8020.

## Deploy

The restore is already done — `/docker-data/hermes-agent` holds the imported
state, with `config.yaml` repointed and credentials moved out of `.env`
(originals kept as `config.yaml.bak.pre-docker01` and `.env.bak.pre-docker01`).
To redo it from scratch:

```bash
# Container must be stopped; the script refuses a non-empty destination.
ssh zbardwell@hermes 'cat ~/hermes-backup-2026-08-07-150039.zip' \
  | ssh root@docker01 'cat > /tmp/hermes-backup.zip'
ssh root@docker01 '/root/homelab-docker/hermes-agent/scripts/restore-backup.sh /tmp/hermes-backup.zip'
```

Then:

```bash
ssh root@docker01 'bash -l -c "/root/homelab-docker/deploy.sh hermes-agent"'
```

`restore-backup.sh` filters the archive:

- **`node/`, `bin/`** — 252 of 262 MB. A vendored Node runtime plus
  `uv`/`uvx`/`tirith`, all host-arch binaries from the old machine. The image
  ships its own at `/opt/hermes`, root-owned and read-only to the runtime user.
- **`*.lock`, `processes.json`** — locks held by processes on the old host and
  a PID table that means nothing here.
- **`gateway_state.json` is kept** — the boot reconciler reads it to decide
  which profiles to start, and it's what makes the gateway come back after a
  container restart.

## Carried over from the old host

Two things in the restored `config.yaml` don't survive the move:

**`mcp_servers.truenas`** spawns `/home/zbardwell/.local/bin/truenas-mcp`, a
path that doesn't exist in the container, and holds a **plaintext TrueNAS API
key** in `config.yaml`. Either disable it (NetBox and the rest of the homelab
are already reachable through the MCPJungle `homelab` server) or re-add it as
an MCPJungle upstream, where the credential lives in that stack's
`.env.register.tpl` instead. The key is worth rotating either way — it has sat
in a backup zip in a home directory.

**`terminal.backend: local`** meant "the `hermes` host" before; now it means
"inside this container". That's a tighter blast radius, but the agent loses
access to anything it used to reach on that box.

## Secrets

`MCP_HOMELAB_API_KEY`, `DISCORD_BOT_TOKEN` and `GITHUB_TOKEN` are injected via `op run`
(`.env.tpl`) rather than left in the data dir's `.env`. Anything in that file
is listed by `GET /api/env` and editable through the dashboard — and by the
agent. Injected env vars are neither.

The rest of the restored `.env` is non-secret tuning (`TERMINAL_*`,
`BROWSER_*`, `*_DEBUG`) and stays as-is.

## Sub-agents

`default` is the front door — it owns the Discord gateway and the kanban
dispatcher. Specialist work is split into separate **profiles**, each with its
own `SOUL.md`, memory, and tool surface, under `profiles/` in this repo.
`scripts/sync-profiles.sh` applies them; see `profiles/README.md` for what a
soul is, the 3 KB budget, and how enforcement actually works.

They coordinate through the **kanban board** (`/opt/data/kanban.db`), not
through chat. The dispatcher runs inside the gateway
(`kanban.dispatch_in_gateway: true`, 60s tick), claims ready tasks, and spawns
the assigned profile as a child process. Comments are the inter-agent protocol;
parent→child links carry a worker's `kanban_complete(summary=…, metadata=…)`
forward as the next agent's context. Workers never shell out to
`hermes kanban` — the dispatcher injects `HERMES_KANBAN_TASK` and the `kanban_*`
toolset appears in the agent's schema.

```bash
docker exec hermes-agent hermes kanban create "…" --assignee obs --max-runtime 15m
docker exec hermes-agent hermes kanban tail <id>      # follow events
docker exec hermes-agent hermes kanban log  <id>      # the worker's own output
docker exec hermes-agent hermes kanban runs <id>      # attempt history
```

**One agent thinks at a time, by design.** Ports 8020 and 8021 on the GPU box
are the *same* llama-server process — `total_slots: 1` — so extra workers would
queue at the model rather than do anything. Keep `kanban.max_in_progress` at 1
and let the board absorb the queue.

Memory is not the limit: a freshly restarted container runs at 516 MiB with a
worker in flight, the worker itself ~177 MB. The gateway does grow with uptime
(1.43 GB after about a week), so compare against a fresh restart before
concluding a worker leaked.

Each profile authenticates to MCPJungle with its **own** client token whose
`--allow` list is limited to the servers it owns; that ACL, plus read-only
upstream registrations, is what actually bounds an agent. `SOUL.md` documents
the boundary — it does not enforce it.

## Operating

```bash
make logs stack=hermes-agent
docker exec -it hermes-agent hermes              # interactive chat
docker exec hermes-agent hermes gateway status
docker exec hermes-agent hermes -p obs chat -q "…"   # one specialist, directly
```

Per-profile gateway logs rotate at `/opt/data/logs/gateways/<name>/current`;
`docker logs` shows the dashboard plus a supervision breadcrumb.

**Never run a second gateway against this data directory** — session files and
the memory store are not safe for concurrent writes. That includes restarting
the old install on `hermes`.

## Not enabled

The OpenAI-compatible API server (`:8642`) is off. Nothing needs it — the
dashboard and gateway talk inside the container. To turn it on, set
`API_SERVER_ENABLED=true`, `API_SERVER_HOST=0.0.0.0`, and an `API_SERVER_KEY`
of at least 8 characters, then publish or route the port.

Renovate is set to **manual review** for this stack: it's an autonomous agent
with code execution and a self-modifying skill tree. Tags are calver
(`v2026.8.3`), so nothing here is ever classified as a major update and the
repo-wide "never automerge major" rule would not otherwise catch it.
