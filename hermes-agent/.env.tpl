# Hermes Agent secrets. Recreate the `hermes-agent` item in the `docker` vault —
# the previous one was archived when the stack was removed in #166, and Connect
# cannot read an archived item ("could not retrieve item").
#
# These are passed through the container environment rather than left in the
# data dir's own .env. The dashboard exposes GET/PUT /api/env and renders
# stored values (redacted) in the UI — anything written there is editable by
# whoever is logged in, and by the agent itself. Injected env vars are not.
#
# Two fields, not the previous six: this install has no Discord gateway and no
# specialist profiles, so DISCORD_BOT_TOKEN and the three MCP_*_API_KEYs that
# scoped the sub-agents are gone.

# Bearer token for the MCPJungle gateway at https://mcp.calzone.zone/mcp.
# config.yaml references it as ${MCP_HOMELAB_API_KEY}.
#
# This needs a *new* MCPJungle client — the previous install shared the
# `claude-code` client's token, which is still registered but belongs to a
# different consumer. Mint a dedicated one so revoking the agent's access does
# not also cut off Claude Code:
#
#   mcpjungle --registry https://mcp.calzone.zone \
#     create mcp-client hermes-default --allow "<server>,<server>"
#
# The token prints once. Store it on the `hermes-agent` item, never in the data
# dir's .env — see the note at the top of this file. Editing a client's --allow
# list later means delete + recreate, which issues a different token.
MCP_HOMELAB_API_KEY=op://docker/hermes-agent/MCP_HOMELAB_API_KEY

# GitHub PAT. Injected rather than stored so the dashboard cannot read it back
# or hand it to the agent as editable state. Scope it to only what the agent
# actually needs — this is a credential the agent acts with, not just holds.
#
# COMMENTED OUT — there is no value to reference yet. The archived item carries
# the old 40-char PAT, but its scopes are unknown and it has been sitting in an
# archived item since 2026-08-14, so it is not being reused. `op run` fails the
# whole deploy on an unresolvable reference, hence the comment rather than a
# dangling line.
#
# To enable: mint a fresh fine-grained PAT, add it to the `hermes-agent` item as
# GITHUB_TOKEN, uncomment below AND the matching passthrough in
# docker-compose.yaml, then redeploy. Nothing else depends on it — the agent
# simply has no GitHub reach until then.
# GITHUB_TOKEN=op://docker/hermes-agent/GITHUB_TOKEN

# ── Model provider ───────────────────────────────────────────────────────
# Intentionally absent. config.yaml selects a custom provider, not a hosted
# API, so there is no key to inject — the endpoint *is* the credential:
#
#   model.base_url = http://100.123.167.70:8090/v1   (gpu-host, over Tailscale)
#   model.default  = qwen3.8-27b
#
# http, not https — 8090 has no TLS listener. Note this is NOT the 8020 /
# Qwen3.6 endpoint the removed install used; that server is gone. Nothing to
# add here unless the server later grows auth. See readme.md → "Model endpoint".
