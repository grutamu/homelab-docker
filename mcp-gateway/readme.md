# mcp-gateway

[MetaMCP](https://github.com/metatool-ai/metamcp) — aggregates every homelab MCP
server behind one endpoint so Claude connects to a single URL instead of holding
a separate config (and a separate copy of every API token) per client.

- UI: `https://mcp.calzone.zone` — login via Pocket-ID
- Endpoint: `https://mcp.calzone.zone/metamcp/homelab/mcp`

## How it fits together

```
Claude Code ──► mcp.calzone.zone/metamcp/homelab/mcp ──► MetaMCP ──┬─► stdio servers (spawned in-container)
                        (API key)                                  └─► HTTP servers (Home Assistant, …)
```

MetaMCP groups servers into **namespaces**; each namespace is published as an
**endpoint**. Tools can be filtered and renamed per namespace, which matters —
dumping every tool in the lab into one endpoint degrades tool selection. Add a
second namespace/endpoint rather than letting one grow unbounded.

The image is built on `ghcr.io/astral-sh/uv:debian` with Node 20, so `uvx` and
`npx` stdio servers run inside the MetaMCP container. No sidecar per server.

## First-time setup

1. Create the `metamcp` item in the `docker` 1Password vault with fields:
   `POSTGRES_PASSWORD` (alphanumeric only — it is interpolated into
   `DATABASE_URL`), `BETTER_AUTH_SECRET` (`openssl rand -base64 32`),
   `OIDC_CLIENT_ID`, `OIDC_CLIENT_SECRET`.

2. Register an OIDC client in Pocket-ID with callback URL
   `https://mcp.calzone.zone/api/auth/oauth2/callback/oidc`, and put its
   credentials in the fields above.

3. Create the data dir:

   ```bash
   ssh root@docker01 'mkdir -p /docker-data/metamcp/postgres'
   ```

4. Deploy:

   ```bash
   ssh root@docker01 'bash -l -c "/root/homelab-docker/deploy.sh mcp-gateway"'
   ```

5. Sign in at `https://mcp.calzone.zone` via Pocket-ID — the first login
   creates the account. Then create, in order: a namespace `homelab`, an
   endpoint `homelab` bound to it with API-key auth on, and an API key.

   There is no declarative bootstrap on v2.4.22 (see the compose comment), so
   this is manual and lives only in MetaMCP's Postgres — which is why the
   Backrest pre-backup hook dumps that DB.

## Connecting Claude Code

```bash
claude mcp add --transport http homelab \
  https://mcp.calzone.zone/metamcp/homelab/mcp \
  --header "Authorization: Bearer <api-key>"
```

Use `claude mcp add` rather than hand-editing `.mcp.json` — there are open
issues ([#48514](https://github.com/anthropics/claude-code/issues/48514),
[#50464](https://github.com/anthropics/claude-code/issues/50464)) where
`headers` in `.mcp.json` are not attached to requests on some versions.

## Registering servers

Servers are added in the UI (**MCP Servers** → **Add**), then attached to the
`homelab` namespace. Config lives in MetaMCP's Postgres, not in this repo — the
DB is dumped by the Backrest pre-backup hook.

### Home Assistant (HTTP — already running)

Type `Streamable HTTP`, URL `http://homeassistant.calzone.zone:9583/private_<token>`.
This is the existing add-on endpoint, moved off the per-client config.

### NetBox (stdio)

Command `uvx`, args
`--from git+https://github.com/netboxlabs/netbox-mcp-server netbox-mcp-server`.
Set `NETBOX_URL` and `NETBOX_TOKEN` in the server's own env field in the UI.

Upstream credentials deliberately do not go in this stack's `.env.tpl`. Every
stdio server shares this one container's environment, so a token placed there
is readable by all of them — per-server env keeps each one's blast radius to
itself. The cost is that those secrets live in MetaMCP's Postgres rather than
in 1Password, which is why that DB is in the backup set.

### Vetted candidates

Checked 2026-07-25 for maintenance, license, publication channel, and blast
radius. An MCP server here runs with whatever token you give it, so scope the
token to the least the tools actually need.

**Cleared:**

| Service | Server | Why |
|---------|--------|-----|
| Grafana | [`grafana/mcp-grafana`](https://github.com/grafana/mcp-grafana) | Official, 3.3k★, Apache-2.0, updated daily. Official `mcp/grafana` image — run as its own container in streamable-http mode, register as an HTTP upstream |
| NetBox | [`netboxlabs/netbox-mcp-server`](https://github.com/netboxlabs/netbox-mcp-server) | Official, Apache-2.0, read-only by design. Not on PyPI — install from git |
| UniFi | [`sirkirby/unifi-mcp`](https://github.com/sirkirby/unifi-mcp) | 570★, MIT, active. Publishes `unifi-network-mcp` / `unifi-protect-mcp` to PyPI |
| TrueNAS | [`truenas/truenas-mcp`](https://github.com/truenas/truenas-mcp) | Official TrueNAS org, GPL-3.0, active, dry-run mode on writes. Not on PyPI — install from git |

**Cleared with caution:**

| Service | Server | Caveat |
|---------|--------|--------|
| Proxmox | [`RekklesNA/ProxmoxMCP-Plus`](https://github.com/RekklesNA/ProxmoxMCP-Plus) | 348★, MIT, active, on PyPI as `proxmox-mcp-plus`. Individual maintainer, not Proxmox official, and the tools start/stop/delete VMs. Use a scoped PVE user, not root@pam |

**Rejected:**

| Server | Reason |
|--------|--------|
| [`shaktech786/arr-suite-mcp-server`](https://github.com/shaktech786/arr-suite-mcp-server) | 7★/8 forks, no commits since 2025-11-08, sole release v1.0.0. Effectively unmaintained, and it would hold Plex plus every *arr key |
| [`nloui/paperless-mcp`](https://github.com/nloui/paperless-mcp) | No license at all — no grant of rights to use it. Unmaintained since 2025-11-11. Its documented `npx paperless-mcp` install is dead: the npm package was **unpublished** two minutes after publication in Dec 2024, so that name is an unclaimed supply-chain slot, not the project |

## Notes

- Image `2.4.22` is the newest published tag (Dec 2025), but upstream commits
  continue on `main` through mid-2026 without a tagged release. Renovate will
  pick up the next tag; don't switch to `latest` just to get ahead of it.
- Not behind `pocket-id-auth@file`. MCP clients can't complete a forward-auth
  browser redirect, so the Traefik middleware would break the endpoint.
  MetaMCP handles UI auth (OIDC) and endpoint auth (API key) itself.
- Traefik's global 600s read/idle/write timeouts already cover long-lived
  SSE and streamable-HTTP sessions.
