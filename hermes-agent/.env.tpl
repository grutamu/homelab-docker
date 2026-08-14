# Hermes Agent secrets. Create the `hermes-agent` item in the `docker` vault.
#
# These are passed through the container environment rather than left in the
# data dir's own .env. The dashboard exposes GET/PUT /api/env and renders
# stored values (redacted) in the UI — anything written there is editable by
# whoever is logged in, and by the agent itself. Injected env vars are not.
#
# The restored backup's .env still carries the non-secret tuning knobs
# (TERMINAL_*, BROWSER_*, *_DEBUG). Only credentials moved here.

# Bearer token for the MCPJungle gateway at https://mcp.calzone.zone/mcp.
# config.yaml references it as ${MCP_HOMELAB_API_KEY}. This is an existing
# MCPJungle client token from the backup, not a new one — re-registering the
# client would issue a different token and require a delete+recreate.
MCP_HOMELAB_API_KEY=op://docker/hermes-agent/MCP_HOMELAB_API_KEY

# Discord gateway. platforms.discord.enabled is true in the restored config,
# so the agent connects and goes live in the home channel on first start.
DISCORD_BOT_TOKEN=op://docker/hermes-agent/DISCORD_BOT_TOKEN

# GitHub PAT. Injected rather than stored so the dashboard cannot read it back
# or hand it to the agent as editable state. Scope it to only what the agent
# actually needs — this is a credential the agent acts with, not just holds.
GITHUB_TOKEN=op://docker/hermes-agent/GITHUB_TOKEN

# ── Sub-agent MCP tokens (one MCPJungle client per profile) ───────────────
# Each specialist profile gets its own MCPJungle client whose --allow list is
# limited to the upstream servers that profile owns. That list is the *auth*
# boundary, not a hint: a token without `proxmox` in its allow-list cannot see
# or invoke a single Proxmox tool, regardless of what the model decides to try.
#
# Distinct variable names matter. Kanban workers are spawned by the dispatcher
# inside this container and inherit its whole environment, so every profile can
# read every one of these. What keeps them apart is that each profile's own
# config.yaml interpolates only its own name — combined with the server-side
# ACL, a profile that reached for the wrong variable would still be refused.
#
# Create with:
#   mcpjungle --registry https://mcp.calzone.zone \
#     create mcp-client hermes-<profile> --allow "<server>,<server>"
# The token prints once. Store it on the `hermes-agent` item, never in the data
# dir's .env — see the note at the top of this file.

# obs — the diagnostician. Grafana only, which is read-only on two independent
# levels (Viewer service account + --disable-write), so this is the one
# specialist that cannot mutate anything even if it tries.
MCP_OBS_API_KEY=op://docker/hermes-agent/MCP_OBS_API_KEY

# ── Model provider ───────────────────────────────────────────────────────
# Intentionally absent. config.yaml selects a custom provider, not a hosted
# API, so there is no key to inject — the endpoint *is* the credential:
#
#   model.base_url = http://100.123.167.70:8020/v1   (the RTX 3090 box, over
#                                                     Tailscale, not the LAN)
#   model.default  = Qwen3.6-27B-Q4_K_M.gguf
#
# http, not https — 8020 has no TLS listener. Nothing to add here unless the
# server later grows auth. See readme.md → "Model endpoint".
