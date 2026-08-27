# Hermes Agent

An autonomous agent with the homelab's MCP tool surface, reachable through a
web dashboard at `hermes.calzone.zone`. Inference runs on gpu-host, not here.

This is a **stock install** of the stack removed in #166. That one had a
Discord gateway, five specialist sub-agent profiles with souls versioned in
git, a kanban board they coordinated through, a sync script that pushed those
profiles into the container, and state restored from the pre-Docker host. None
of it came back. What is here is the container, one MCPJungle token, and an
empty data dir — the agent runs on its own defaults.

```
docker-compose.yaml   the container, the dashboard, the Traefik route
.env.tpl              one secret, injected via `op run`
```

Everything else lives in `/docker-data/hermes-agent` and belongs to the agent:
config, memories, sessions, and any skills it writes for itself. **None of that
is in git**, and nothing in this repo pushes into it. If you later want the
agent's identity or tool scoping under review, that is the thing to add back —
see #166's `profiles/` and `scripts/sync-profiles.sh` for the shape it had.

## Why this diverges from upstream's compose

Upstream uses `build: .` and `network_mode: host`. Neither is needed: the
published image is on Docker Hub, and host networking is only required when the
dashboard runs as a separate container. One container with `HERMES_DASHBOARD=1`
supervises both under s6, so bridge + `proxy` works and Traefik routes to it
normally.

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

With Discord gone, this dashboard is the **only** interface. If OIDC is
misconfigured there is no second door.

### One-time pocket-id client

`docker-compose.yaml` still carries the client UUID from the removed install
(`763e47b3-…`). #166's teardown notes left deleting that client to a human, so
it may or may not still exist. **Verify before first login** — a deleted client
fails the token exchange on an `aud` mismatch, which presents as a login loop
rather than a config error.

If it needs recreating, in pocket-id at `https://auth.calzone.zone`:

| Field | Value |
|---|---|
| Name | `hermes-dashboard` |
| Type | **Public** (PKCE / S256) — confidential clients with a secret are not supported |
| Callback URL | `https://hermes.calzone.zone/auth/callback` |
| Scopes | `openid profile email` |

pocket-id mints its own client ID and does not let you choose one — the name
above is only a display name. Paste the **generated UUID** into
`HERMES_DASHBOARD_OIDC_CLIENT_ID`; Hermes pins the ID token's `aud` claim to
whatever is set there, so a friendly name fails the exchange.

Verify the gate is live once it's up:

```bash
curl -s https://hermes.calzone.zone/api/status | jq '.auth_required, .auth_providers'
# true
# ["self-hosted"]
```

### DNS: the hostname collides with a real machine

`hermes.calzone.zone` resolves **differently depending on which resolver you
ask**, because the GPU box is itself named `hermes`:

| Resolver | Answer |
|---|---|
| AdGuard (`192.168.99.5`) — normal clients | `docker-01.calzone.zone` → `192.168.99.41` ✓ |
| UDM (`192.168.99.1`) — what docker01 itself uses | `192.168.1.43` (the GPU box) ✗ |

adguard-sync creates the correct rewrite automatically, so browsers on the LAN
reach the dashboard fine. But docker01's own `resolvectl` points at the UDM,
not AdGuard, and the UDM answers with the physical host.

Nothing in this stack resolves its own hostname, so it works. It is still a
latent trap — renaming the router to `hermes-agent.calzone.zone` (matching the
container and stack name) would remove the ambiguity. That means changing the
Traefik rule, `HERMES_DASHBOARD_PUBLIC_URL`, and the pocket-id client's
callback URL together.

## Model endpoint

The model is a **custom provider**, not a hosted API, so there is no key — the
endpoint *is* the credential. Anything that can reach port 8090 can use it.

**This is not where the removed install pointed.** That one used
`http://100.123.167.70:8020/v1` with
`/models/qwen3.6-27b-gguf/…/Qwen3.6-27B-Q4_K_M.gguf`. Port 8020 no longer
answers; gpu-host now serves Qwen3.8-27B on **8090**, and the model ID is the
short name `qwen3.8-27b`, not a path. Verified from docker01 over Tailscale:
`/v1/models` returns the 27B (`n_ctx: 262144`, IQ4_XS), and a function-calling
round-trip returns well-formed `tool_calls` with `finish_reason: tool_calls` in
~0.9 s on `b10236`. That last check matters — Hermes is tool-call-driven, and
`/v1/models` advertises only `completion` and `multimodal` in `capabilities`.

Addressed over **Tailscale**, not the LAN IP (`192.168.1.43`, which also
works). docker01 and gpu-host sit on different subnets, so the LAN path depends
on inter-VLAN routing staying as it is; the Tailscale address does not, and the
traffic is encrypted in transit. It is `http` — 8090 has no TLS listener.

gpu-host runs a **variant-switching estate** (`launch.sh --variant …`); each
variant is its own container and the endpoint is down between switches, which
is also why the `gpu-host-llama` Prometheus target flaps by design (see
[docs/gpu-host-llama.md](../docs/gpu-host-llama.md)). A variant that binds a
different port leaves the agent with no model. Nothing here restarts it.

### Pointing the agent at it — one-time, by hand

A fresh data dir has no `custom_providers`, and **the CLI cannot create one**.
It is a YAML list, and `hermes config set custom_providers.0.name …` writes a
dict keyed `'0'` (doctor: *"custom_providers is a dict — it must be a YAML
list"*), while `--force` stores the JSON as a literal string. There is no
generic `openai` provider to fall back on; that name is rejected too. The
removed install sidestepped this by inheriting a valid list from its restored
backup.

So the list is written once, by hand, against a stopped container:

```bash
ssh root@docker01 'docker stop hermes-agent'
# Append to /docker-data/hermes-agent/config.yaml:
#   custom_providers:
#     - name: "Local (gpu-host:8090)"
#       base_url: http://100.123.167.70:8090/v1
#       api_key: ""
ssh root@docker01 'docker start hermes-agent'
```

The three settings that *select* it are plain scalars, so they go through the
supported write path once the list exists:

```bash
ssh root@docker01 'docker exec hermes-agent hermes config set model.provider "custom:Local (gpu-host:8090)"
docker exec hermes-agent hermes config set model.base_url http://100.123.167.70:8090/v1
docker exec hermes-agent hermes config set model.default qwen3.8-27b
docker exec hermes-agent hermes doctor'
```

The hand edit is the one place upstream's never-edit-config.yaml rule gets
broken, and only because the supported write path does not cover a YAML list.

## Deploy

```bash
ssh root@docker01 'install -d -o 1000 -g 1000 /docker-data/hermes-agent'
ssh root@docker01 'bash -l -c "/root/homelab-docker/deploy.sh hermes-agent"'
```

The data dir must exist and be owned by `1000:1000` before the first start —
that matches `HERMES_UID`/`HERMES_GID`, which the s6 stage2 hook remaps the
container's `hermes` user to. Files owned by root are files the agent cannot
read.

Then bootstrap the provider, above. Until that is done the agent has no model.

## Secrets

`MCP_HOMELAB_API_KEY` is injected via `op run` (`.env.tpl`) rather than left in
the data dir's `.env`. Anything in that file is listed by `GET /api/env` and
editable through the dashboard — and by the agent. Injected env vars are not.

The original `hermes-agent` 1Password item was **archived** when #166 removed
this stack, and Connect cannot read an archived item. A fresh item was created
on 2026-08-27 with a single field; the archived one is left alone as an audit
trail.

`MCP_HOMELAB_API_KEY` is a **new** `hermes-default` MCPJungle client, not the
`claude-code` token the previous install shared — so revoking the agent does
not also cut off Claude Code. Its `--allow` list is
`proxmox,unifi_network,home_assistant,grafana,adguard,netbox`, full parity with
the removed install.

**That allow-list is the only enforced boundary.** The removed install layered
a versioned `SOUL.md` on top of it telling the agent to never infer approval
for a destructive action; a stock install has no such file. The list includes
the full-Administrator `proxmox` credential and UniFi's `unifi_execute`, which
fronts ~200 tools including firewall deletion — so nothing but the agent's own
judgment stands between it and a destructive call. Narrowing the client means
delete + recreate, which issues a different token.

`GITHUB_TOKEN` is **not set**. The archived item's 40-char PAT was not reused
(unknown scopes, archived since 2026-08-14). Both the `.env.tpl` line and the
compose passthrough are commented out; uncomment them together after minting a
fresh fine-grained PAT and adding it to the item.

## Operating

```bash
make logs stack=hermes-agent
docker exec -it hermes-agent hermes              # interactive chat
docker exec hermes-agent hermes gateway status
docker exec hermes-agent hermes doctor
```

Gateway logs rotate under `/opt/data/logs/gateways/`; `docker logs` shows the
dashboard plus a supervision breadcrumb.

**Never run a second gateway against this data directory** — session files and
the memory store are not safe for concurrent writes.

Memory: expect ~500 MiB fresh. The gateway grows with uptime (the previous
install reached 1.43 GB after about a week), so compare against a fresh restart
before concluding something leaked. `mem_limit: 4g` is a ceiling, not a
reservation — it is there so a runaway loop can't repeat what MetaMCP did to
this host on 2026-07-25.

## Not enabled

- **Discord.** No `DISCORD_BOT_TOKEN`, no gateway. The bot application from the
  previous install may still exist in the Discord developer portal.
- **Sub-agents and kanban.** One agent, nothing to dispatch to. The
  `proxmox_ro` MCPJungle registration that once backed the `virt` specialist is
  still there and still useful as a read-only Proxmox path.
- **The OpenAI-compatible API server** (`:8642`). Nothing needs it — the
  dashboard and gateway talk inside the container. To turn it on, set
  `API_SERVER_ENABLED=true`, `API_SERVER_HOST=0.0.0.0`, and an `API_SERVER_KEY`
  of at least 8 characters, then publish or route the port.
- **Backup restore.** The data dir starts empty; the previous install's
  memories and sessions are not carried forward.

Renovate is set to **manual review** for this stack: it's an autonomous agent
with code execution and a self-modifying skill tree. Tags are calver
(`v2026.8.19`), so nothing here is ever classified as a major update and the
repo-wide "never automerge major" rule would not otherwise catch it.
