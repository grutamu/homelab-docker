# mcpjungle

[MCPJungle](https://github.com/mcpjungle/MCPJungle) — aggregates every homelab
MCP server behind one endpoint so Claude connects to a single URL instead of
holding a separate config (and a separate copy of every API token) per client.

Replaces the MetaMCP `mcp-gateway` stack, removed 2026-07-26 after it leaked
uvx stdio subprocesses and drove docker01 into a global OOM.

- Endpoint: `https://mcp.calzone.zone/mcp`
- Management: `mcpjungle` CLI (no web UI — see below)

## How it fits together

```
Claude Code ──► mcp.calzone.zone/mcp ──► MCPJungle ──┬─► stdio servers (spawned in-container)
                  (client bearer token)              └─► HTTP servers (Home Assistant, …)
```

MCPJungle groups tools into **tool groups**, each published at its own endpoint.
Prefer a group over dumping every tool in the lab into `/mcp` — a large
undifferentiated tool list degrades selection. (Groups currently expose tools
only, not prompts or resources; `/mcp` surfaces everything.)

## Mode: enterprise, and what that costs

`SERVER_MODE=enterprise` is set because it is the only mode with authentication.
In `development` mode any client that can reach the endpoint gets every tool.

The trade-off is that **the dashboard UI is development-mode only**, so there is
nothing to visit in a browser at `mcp.calzone.zone` — management happens through
the CLI. The Traefik router exists to serve `/mcp` to clients.

The router deliberately has no `pocket-id-auth@file` middleware: MCP clients
can't complete a forward-auth browser redirect, so it would break the endpoint.
MCPJungle authenticates clients itself with static per-client bearer tokens.
It does not yet support OIDC for downstream clients, so pocket-id can't front
this the way it fronts the other services.

## First-time setup

1. Create the `mcpjungle` item in the `docker` 1Password vault with fields:
   `POSTGRES_PASSWORD` (`openssl rand -base64 32`), plus every field listed in
   `.env.register.tpl` — that includes the upstream hosts and ports, not just
   the tokens.

2. Rotate the Proxmox API token first. MetaMCP wrote `claude@pam!mcp-token`
   into its container logs in plaintext; that value is burned. The UniFi
   account's password went through the same path and should be rotated too.

3. Deploy. There is no data dir to create — Postgres uses a named volume, which
   Docker creates on first start:

   ```bash
   ssh root@docker01 'bash -l -c "/root/homelab-docker/deploy.sh mcpjungle"'
   ```

4. Bootstrap the admin identity. This is a one-time step against a fresh
   enterprise server; it prints the admin token and writes it to
   `~/.mcpjungle.conf` on whatever machine you run it from:

   ```bash
   mcpjungle --registry https://mcp.calzone.zone init-server
   ```

   Store that token in 1Password — there is no way to reprint it.

5. Reload Prometheus. `deploy.sh` runs `docker compose up -d`, which only
   recreates a container when its *compose* config changes — editing the
   bind-mounted `prometheus.yaml` alone leaves Prometheus running the old
   config, so a new scrape target silently never appears. Prometheus runs with
   `--web.enable-lifecycle`, so:

   ```bash
   ssh root@docker01 'docker exec prometheus wget -q --post-data="" -O- \
     http://localhost:9090/-/reload'
   ```

   Verified on 2026-07-28: both the `mcpjungle` scrape and the blackbox probe
   of `/health` answer **without** auth and report `up`. The container
   publishes no host ports (Traefik-only), so check from inside the network —
   `docker exec prometheus wget -qS -O /dev/null http://mcpjungle:8080/metrics`
   — not from `localhost:8080` on the host, which is unreachable by design.

## Registering servers

Unlike MetaMCP, server definitions live in this repo (`servers/*.json`) rather
than only in the gateway's database. Every environment-specific value — hosts,
ports, usernames, tokens — stays out of them via `${VAR}` placeholders, which
the CLI resolves from its own environment at registration time and hands to the
server for per-server storage. The committed configs record only the package
and its shape, never where the backends live or how to reach them.

```bash
op run --env-file=.env.register.tpl -- \
  mcpjungle register -c ./servers/home-assistant.json

op run --env-file=.env.register.tpl -- \
  mcpjungle register -c ./servers/proxmox.json

op run --env-file=.env.register.tpl -- \
  mcpjungle register -c ./servers/unifi.json
```

Register them **one at a time**, checking `docker stats mcpjungle` between each.
The failure mode being guarded against here is a slow leak, not a fast crash.

Upstream values deliberately do not go in this stack's `.env.tpl`. Every stdio
server inherits the gateway container's environment, so anything placed there is
readable by all of them — per-server env keeps each one's blast radius to itself.

### Notes on the individual servers

- **Home Assistant** (`ha-mcp`) talks to the HA REST API with a long-lived
  access token, minted on the HA user profile page. It is not the old add-on
  endpoint that carried its token in the URL path. Note it spawns a persistent
  `ha_mcp.stdio_settings_sidecar` process (~83 MB) that outlives the tool call
  despite `session_mode: stateless` — so this server is not as stateless as the
  setting implies. One sidecar is fine inside the 2g cap; watch that it stays
  at one rather than accumulating per call.
- **Proxmox** (`proxmox-mcp-plus`) has tools that start, stop and delete VMs.
  Scope `claude@pam` to the least those tools actually need. It points at
  `proxmox.calzone.zone:443` — the Traefik file-provider route — rather than
  `192.168.10.10:8006` directly. 0.5.10 hard-refuses `verify_ssl=false` unless
  `PROXMOX_DEV_MODE=true`, and Proxmox serves a self-signed cert on 8006, so
  going direct means turning TLS verification off. Traefik already absorbs the
  self-signed backend via `serversTransport: proxmox-insecure` and presents a
  real Let's Encrypt cert, so this path verifies properly with no override.
  Cost: the server now depends on Traefik being up.
- **UniFi** (`unifi-network-mcp`) needs a dedicated local admin account without
  MFA, not Ubiquiti SSO credentials.

Both stdio servers are pinned to an exact PyPI version rather than `@latest`.
`@latest` re-resolves on every cold start, which makes the tool surface change
without a commit and puts an unreviewed package one upload away from running
in the container.

Also cleared during the 2026-07-25 vetting pass but not registered here:
[`netboxlabs/netbox-mcp-server`](https://github.com/netboxlabs/netbox-mcp-server)
(stdio, install from git — not on PyPI),
[`grafana/mcp-grafana`](https://github.com/grafana/mcp-grafana) (run as its own
container in streamable-http mode and register as an HTTP upstream), and
[`truenas/truenas-mcp`](https://github.com/truenas/truenas-mcp).

## Connecting a client

Create a client identity with an explicit allow-list — not `--allow "*"`:

```bash
mcpjungle create mcp-client claude-code --allow "home_assistant,proxmox,unifi_network"
```

The token is printed once. Then:

```bash
claude mcp add --transport http homelab https://mcp.calzone.zone/mcp \
  --header "Authorization: Bearer <client-token>"
```

Use `claude mcp add` rather than hand-editing `.mcp.json` — there are open
issues ([#48514](https://github.com/anthropics/claude-code/issues/48514),
[#50464](https://github.com/anthropics/claude-code/issues/50464)) where
`headers` in `.mcp.json` are not attached to requests on some versions.

## Guardrails against a repeat OOM

The previous gateway took the host down because nothing bounded it. Four things
here are load-bearing for that, not incidental:

- `mem_limit: 2g` — stdio children share the container's cgroup, so this caps
  the whole process tree. docker01 has no per-container limits otherwise.
- `init: true` — tini as PID 1, reaping orphaned children. MCPJungle as PID 1
  does not `wait()` on them: a `[uv] <defunct>` zombie per registration was
  observed on 2026-07-28. Zombies cost no memory but do consume PIDs, so this
  is the same unbounded-accumulation failure by another route.
- `SESSION_IDLE_TIMEOUT_SEC=300` — the default is `-1`, meaning stateful
  sessions live until the process exits. That's the shape of the MetaMCP leak.
- `session_mode: stateless` in every config in `servers/` — a process per tool
  call, torn down after. Only switch a server to `stateful` if cold start
  actually becomes a bottleneck, and only with the idle timeout above in place.
- Prometheus scrapes `/metrics`; `container_alerts.yml` covers memory. Watch
  `container_memory_usage_bytes{name="mcpjungle"}` after registering anything.

MCPJungle handles `SIGTERM` by closing active sessions and flushing telemetry
before exit, so `docker stop` is a clean shutdown rather than an orphan factory.

## Notes

- Postgres lives on a **named volume**, not a `/docker-data` bind mount like
  every other stack here. That means Backrest's file-level sweep of
  `/docker-data` does not see the data dir, and the pre-backup `pg_dump` to
  `/docker-data/db-dumps/mcpjungle.sql` is the *only* backup of this DB —
  which holds the admin token, every client token and ACL, and the credentials
  for all three upstream servers. Little is lost in practice: a file-level copy
  of a running Postgres data dir is torn and not a reliable restore source
  anyway. But `pre-backup.sh` runs under `set -e`, so if that dump ever starts
  failing the whole backup run aborts rather than silently shipping snapshots
  without this DB — check backup failures here first.
- Restoring is therefore dump-only:
  `docker exec -i mcpjungle-postgres psql -U mcpjungle mcpjungle < /docker-data/db-dumps/mcpjungle.sql`
- The `-stdio` image tag is required; the plain tag ships the binary alone and
  can't spawn `uvx`/`npx` servers. Renovate tracks the tag, so it stays on the
  `-stdio` suffix across bumps.
- Traefik's global 600s read/idle/write timeouts already cover long-lived
  streamable-HTTP sessions.
