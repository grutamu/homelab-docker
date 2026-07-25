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
   `POSTGRES_PASSWORD`, `BETTER_AUTH_SECRET` (`openssl rand -base64 32`),
   `OIDC_CLIENT_ID`, `OIDC_CLIENT_SECRET`, `BOOTSTRAP_USER_EMAIL`,
   `BOOTSTRAP_USER_PASSWORD`.

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

5. Log in, open **API Keys**, and copy the bootstrapped `claude` key.

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
`NETBOX_URL` / `NETBOX_TOKEN` are already on the container from 1Password.

> Verify token inheritance after the first deploy — if the spawned server can't
> see `NETBOX_TOKEN`, MetaMCP isn't forwarding the parent environment to stdio
> children, and the value has to be set in the server's own env field in the UI.

### Others worth adding

Verified as real, actively maintained projects — each still needs its own token
in 1Password before wiring up:

| Service | Server |
|---------|--------|
| Grafana | [`grafana/mcp-grafana`](https://github.com/grafana/mcp-grafana) — official; run as its own container in streamable-http mode and register as an HTTP upstream |
| Portainer | [`portainer/portainer-mcp`](https://github.com/portainer/portainer-mcp) — official |

Paperless, Immich, Frigate, Plex and the *arr suite all have community MCP
servers of varying quality. Vet each one before pointing it at a service that
holds real data — an MCP server registered here runs with whatever token you
give it.

## Notes

- Image `2.4.22` is the newest published tag (Dec 2025), but upstream commits
  continue on `main` through mid-2026 without a tagged release. Renovate will
  pick up the next tag; don't switch to `latest` just to get ahead of it.
- Not behind `pocket-id-auth@file`. MCP clients can't complete a forward-auth
  browser redirect, so the Traefik middleware would break the endpoint.
  MetaMCP handles UI auth (OIDC) and endpoint auth (API key) itself.
- Traefik's global 600s read/idle/write timeouts already cover long-lived
  SSE and streamable-HTTP sessions.
