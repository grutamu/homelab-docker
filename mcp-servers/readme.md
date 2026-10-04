# MCP servers

The homelab's MCP tool surface: one HTTP MCP server per upstream, each in its
own container, all fronted by a **Cloudflare MCP server portal** at
`https://mcp-portal.calzone.zone/mcp`. Replaced MCPJungle on 2026-10-03.

```
MCP client ──OAuth (Cloudflare Access, one-time PIN)──► mcp-portal.calzone.zone/mcp
                                                              │ Gateway → docker-01 tunnel
                                                              │ (private CIDR route 172.30.100.0/24)
                                                              ▼
                     cf-tunnel (infra) ── mcp-servers network ──┬─ 172.30.100.10:8000/mcp  grafana-mcp
                                                                ├─ 172.30.100.11:8000/mcp  netbox-mcp
                                                                ├─ 172.30.100.12:8000/mcp  proxmox-ro-mcp
                                                                ├─ 172.30.100.13:8086/<secret>  ha-mcp
                                                                ├─ 172.30.100.14:3000/mcp  unifi-mcp
                                                                └─ 172.30.100.15:3000/     adguard-mcp
```

```
docker-compose.yaml              the six servers, static IPs on `mcp-servers`
.env.tpl                         upstream credentials + the portal→server tokens
scripts/grafana-service-account.sh   (re)mint the Viewer token for grafana-mcp
```

## Why it looks like this

- **No Traefik route, no published ports.** The only way in is `cf-tunnel` on
  the `mcp-servers` network, which `infra` owns (it deploys first, and
  cf-tunnel has to join it). unifi and adguard have no auth of their own, so
  this isolation is what protects them. Don't add a Traefik label "for local
  access" — that would put two unauthenticated control APIs on the LAN.
- **Static IPs, because they are the portal's server URLs.** Changing one means
  `cf mcp servers update <id>` too.
- **A bearer token on every server that supports one** (grafana, netbox,
  proxmox-ro). The portal stores the same value and presents it. ha-mcp has no
  bearer option outside OIDC mode, so its credential is a high-entropy URL path
  (`HA_MCP_SECRET_PATH`) that is part of the portal's server URL.
- **Per-container `mem_limit`.** Under MCPJungle every upstream was a stdio
  child sharing one 2g cgroup; here each is a long-lived process with its own
  cap, so a leak in one can't starve the rest.
- **Images, not `uvx` pins.** Renovate tracks these tags like any other stack,
  with manual review (see `renovate.json`).

## Cloudflare side

All of this was created with the `cf` CLI (`npm i -g cf`, `cf auth login`).
Account `b4341433eedc051f29073ba3c6dbf9fe`, zone `calzone.zone`.

| Object | Identity |
|---|---|
| Tunnel | `docker-01` (`b7c81b64-…`), run by `infra/cf-tunnel`, remotely managed, warp-routing on |
| Private route | `172.30.100.0/24` → `docker-01` |
| MCP servers | `grafana`, `netbox`, `proxmox-ro`, `home-assistant`, `unifi-network`, `adguard` — all `secure_web_gateway: true` |
| MCP portal | `homelab` on `mcp-portal.calzone.zone`, `code_mode: opt_in`, every server `on_behalf: false` |
| DNS | `mcp-portal` CNAME → `gateway.agents.cloudflare.com`, proxied |
| Access apps | `Homelab MCP portal` (type `mcp_portal`) + one `Homelab MCP — <server>` (type `mcp`, destination `via_mcp_server_portal`) per server |
| Access policy | `Homelab owner` (reusable) — the two owner email addresses, 168h session |
| Identity provider | One-time PIN |
| Hosted MCP servers | `cloudflare-api`, `cloudflare-dns-analytics`, `cloudflare-audit-logs`, `github` (OAuth, `on_behalf: true`); `cloudflare-docs` (unauthenticated) — see below |

### Hosted servers on the same portal

Not everything on the portal runs here. These are public, vendor-hosted MCP
servers added directly to `homelab` — no container, no tunnel, no stored
credential:

| Server id | URL | Auth |
|---|---|---|
| `cloudflare-api` | `https://mcp.cloudflare.com/mcp` | per-user OAuth, read-only scopes — acts as the signed-in user |
| `cloudflare-dns-analytics` | `https://dns-analytics.mcp.cloudflare.com/mcp` | per-user OAuth |
| `cloudflare-audit-logs` | `https://auditlogs.mcp.cloudflare.com/mcp` | per-user OAuth |
| `cloudflare-docs` | `https://docs.mcp.cloudflare.com/mcp` | none |
| `github` | `https://api.githubcopilot.com/mcp/` | per-user OAuth — acts as the signed-in GitHub user |

OAuth servers sit at `status: waiting` with no tools until the first user
authorizes them through the portal; that first grant is what syncs the tool
list. They're `on_behalf: true`, so each user connects their own account, and
an Access service token (e.g. Hermes) never sees them. Each still needs its own
`type: mcp` Access app like the local servers.

**All four use manual OAuth (`auth_mode: manual`), not the portal's automatic
registration** — a server the portal can't register a client for is silently
left off the connect screen, with no error anywhere. What it took:

- `auth_credentials` is a **JSON-encoded string**, not an object (`[7001]
  Expected string, received object`), and with `--body` the CLI's
  `--client-secret` flag is ignored — put `client_secret` inside the body.
- Manual mode requires a `client_secret`, so the client must be confidential.
- Redirect URI is the shared callback
  `https://oauth-callbacks.cloudflareaccess.com/cdn-cgi/access/outbound-oauth-callback`,
  with `is_shared_oauth_callback_enabled: true`.
- **GitHub**: no dynamic client registration. A GitHub OAuth App (owner's
  account, client id `Ov23liKJeZJ5qoaN9uPH`) with that callback; scopes
  `repo read:org read:user notifications`.
- **Cloudflare**: they do support registration, but the portal's own attempt
  never produced a connectable server. Clients were registered by hand against
  each server's `/register` with `token_endpoint_auth_method:
  client_secret_basic` — `client_secret_post` fails the token exchange with
  "invalid client". `cloudflare-api` requests only the `*.read` scopes (+
  `user:read account:read offline_access`); widening it means re-registering.

To rotate one of these secrets, re-register (Cloudflare) or regenerate in the
GitHub OAuth App, then `cf mcp servers update <id>` with the full body,
`client_secret` included — the update is a PUT, so omitted fields are dropped.

Things the API does **not** do that the dashboard does — if you ever recreate
this by hand:

- **The DNS record.** Without it the hostname doesn't resolve; with it created
  *after* the portal, expect a few seconds of `error code: 1014` while the
  hostname binds.
- **The portal's Access application.** Create it with `type: mcp_portal` and
  `domain` set to the portal hostname.
- **One Access application per server.** The portal only shows a user the
  servers whose application admits them — without these, login succeeds and
  then reports "No allowed servers available".
- **`on_behalf: false`.** New portal-server links default to `true` (per-user
  OAuth). These servers use static credentials, and service tokens skip
  `on_behalf: true` servers entirely.

Useful checks:

```bash
export CLOUDFLARE_ACCOUNT_ID=b4341433eedc051f29073ba3c6dbf9fe
cf mcp servers list -q | jq -r '.[] | "\(.id) \(.status) \(.tools|length)"'
cf mcp portals read homelab -q | jq '.servers[] | {server_id, status, on_behalf}'
cf mcp portals tool-call-analytics homelab
```

`status: ready` with a tool count means Cloudflare reached the server through
the tunnel and synced it — the end-to-end private path works.

## Connecting a client

**Interactive (Claude Code, claude.ai, etc.)** — no token to paste; the client
runs OAuth against Access and you sign in with a one-time PIN to an allowed
address:

```bash
claude mcp add --transport http --scope user homelab https://mcp-portal.calzone.zone/mcp
# then in Claude Code: /mcp → homelab → Authenticate
```

**Non-interactive (hermes-agent)** — an Access **service token**, sent as two
headers. It needs a *Service Auth* policy (decision `non_identity`, include the
token) added to the portal's Access app **and** every server's Access app;
`Homelab owner` alone will reject it.

```yaml
mcp_servers:
  homelab:
    url: https://mcp-portal.calzone.zone/mcp
    headers:
      CF-Access-Client-Id: ${CF_ACCESS_CLIENT_ID}
      CF-Access-Client-Secret: ${CF_ACCESS_CLIENT_SECRET}
```

Every client sees the same tools. A portal has no per-user tool sets — to give
a client a narrower surface, make a second portal with fewer servers and its
own policy, not a per-client allow-list.

## Adding a server

1. Add a container here with the next free IP, no labels, no ports, its own
   `mem_limit`, and a bearer token if it supports one (new field on the
   `mcp-servers` 1Password item + a line in `.env.tpl`).
2. Deploy, then probe it from inside the network before touching Cloudflare —
   see *Verifying* below.
3. `cf mcp servers create --body '{"id":…,"hostname":"http://172.30.100.N:PORT/mcp","auth_type":"bearer","auth_credentials":…,"secure_web_gateway":true}'`
4. Add it to the portal (`cf mcp portals update homelab` with the full
   `servers` array, `on_behalf: false`) and create its `type: mcp` Access app
   with the `Homelab owner` policy (+ the service-auth policy).

## Rotating a credential

- **Upstream credential** (HA token, UniFi password, …): update the
  `mcp-servers` 1Password item, redeploy. Nothing on the Cloudflare side.
- **Portal → server token** (`*_MCP_AUTH_TOKEN`, `PROXMOX_RO_MCP_API_KEY`,
  `HA_MCP_SECRET_PATH`): update 1Password, redeploy, then
  `cf mcp servers update <id>` with the new `auth_credentials` (or, for HA, the
  new `hostname`). The server is unreachable through the portal between the two.
- **Grafana**: `scripts/grafana-service-account.sh`, then redeploy.

## Verifying

From docker01, an `initialize` + `tools/list` against a server, inside the
network the way the portal sees it:

```bash
docker run --rm --network mcp-servers curlimages/curl:8.16.0 -s -X POST \
  http://172.30.100.11:8000/mcp \
  -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' \
  -H "Authorization: Bearer $(op read op://docker/mcp-servers/NETBOX_MCP_AUTH_TOKEN)" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"probe","version":"1"}}}'
```

Without the `Authorization` header grafana, netbox and proxmox-ro must return
401. Tool counts at cutover: grafana 62, netbox 4, proxmox-ro 53,
home-assistant 77, unifi 208, adguard 29.

## Notes on the individual servers

- **Grafana** (`grafana/mcp-grafana`) — the image entrypoint hard-codes
  `--transport sse`, so the compose file replaces the entrypoint. Read-only on
  two levels: Viewer service account *and* `--disable-write`. Allowing edits
  needs both changed. `--allowed-hosts` is required: host validation defaults
  to loopback, and the portal connects by IP. `GRAFANA_URL` is the container
  (`http://grafana:3000`), which is why this one container also joins `proxy`.
- **NetBox** — `NETBOX_URL` must be the Traefik hostname: netbox enforces
  `ALLOWED_HOST` and returns 400 for the container name. Read-only token.
- **Proxmox** — only the **read-only** credential is served (`privsep=1`,
  PVEAuditor). All 42-odd tools still register, `delete_vm` included; the API
  refuses writes with 403, so the token is the only barrier. The full-admin
  token stays on the 1Password item but nothing serves it — exposing it through
  an internet-reachable portal was ruled out. To restore write access, add a
  second container with those credentials and a separate, tighter portal.
  Goes via `proxmox.calzone.zone:443` (Traefik) because the server refuses
  `verify_ssl=false` outside dev mode and the node's own cert is self-signed.
  `PROXMOX_MCP_CONFIG=/nonexistent` makes it fall back to env vars.
- **Home Assistant** (`ha-mcp`, `ha-mcp-web` entry point) —
  `ENABLE_STRICT_MANDATORY_BPS=false` was needed under MCPJungle, where every
  call spawned a fresh process with a new ack-key salt. This is now one
  long-lived process, so the strict gate *could* work again; it's left off to
  keep behaviour unchanged across the migration. Try turning it on.
  `ha_get_overview` returns a `settings_url_hint` containing the secret path,
  so every portal client can read it. That's tolerable only because the
  container is unreachable except via the tunnel — treat the path as a routing
  value, not as the thing keeping HA safe. (The same path also serves ha-mcp's
  settings UI at `<path>/settings`.)
- **UniFi** — dedicated local admin without MFA. HTTP is opt-in
  (`UNIFI_MCP_HTTP_ENABLED`), Host is validated (`UNIFI_MCP_ALLOWED_HOSTS`),
  and `UNIFI_TOOL_REGISTRATION_MODE=eager` — the default `lazy` exposes only
  meta-tools, which defeats the portal's per-tool toggles. Note env names
  changed from the old stdio pin (`UNIFI_NETWORK_HOST` → `UNIFI_HOST`).
- **AdGuard** — serves MCP at `/`, not `/mcp`. `ADGUARD_ACCESS_TIER=read-only`
  is the *only* write barrier (AdGuard has no scoped tokens; this is the admin
  account `adguard-sync` also uses), and it keeps a model off the rewrites
  `adguard-sync` owns.

## What changed from MCPJungle

- Every tool call now leaves the LAN and comes back through Cloudflare. No
  internet, no tools — including from a machine on the same LAN.
- No per-client allow-lists, no tool groups. Per-tool on/off lives on the
  portal; per-audience surfaces mean separate portals.
- No Postgres, so nothing in the pre-backup dump for this stack — all state is
  in 1Password and Cloudflare.
- Metrics: MCPJungle's Prometheus `/metrics` is gone. Tool-call volume is in
  `cf mcp portals tool-call-analytics`; container health is in cAdvisor like
  everything else.
