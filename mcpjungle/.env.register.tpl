# Upstream MCP server connection details, resolved by the mcpjungle CLI at
# registration time and stored per-server in MCPJungle's Postgres.
#
# Hosts and usernames are in 1Password alongside the tokens, not committed
# here — the servers/*.json configs carry only ${VAR} placeholders, so this
# repo never records where the backends actually live.
#
# Deliberately separate from .env.tpl: deploy.sh only injects .env.tpl into the
# container environment, and every stdio server inherits that environment.
# Keeping these out of it means each server only ever sees its own values.
#
# Usage:
#   op run --env-file=.env.register.tpl -- \
#     mcpjungle register -c ./servers/proxmox.json

# Long-lived access token from the Home Assistant user profile page.
HOMEASSISTANT_URL=op://docker/mcpjungle/HOMEASSISTANT_URL
HOMEASSISTANT_TOKEN=op://docker/mcpjungle/HOMEASSISTANT_TOKEN

# NOTE: the old claude@pam!mcp-token was leaked to container logs by MetaMCP
# and must be rotated in Proxmox before this is registered.
PROXMOX_HOST=op://docker/mcpjungle/PROXMOX_HOST
PROXMOX_PORT=op://docker/mcpjungle/PROXMOX_PORT
PROXMOX_USER=op://docker/mcpjungle/PROXMOX_USER
PROXMOX_TOKEN_NAME=op://docker/mcpjungle/PROXMOX_TOKEN_NAME
PROXMOX_TOKEN_VALUE=op://docker/mcpjungle/PROXMOX_TOKEN_VALUE

# Second Proxmox registration, read-only. Originally added for the `virt`
# Hermes sub-agent (removed 2026-08-14); kept as the read-only path for any
# client that should see Proxmox but never write to it. Same host and port as
# above; only the credential differs.
#
# The scoping lives entirely in this token, NOT in the MCP server —
# proxmox-mcp-plus registers all 42 tools either way, `delete_vm` included.
# They are present in the client's schema and fail at the API with 403. That is
# a weaker shape than Grafana or AdGuard, where the write tools simply do not
# exist, so the token is the only thing standing between a read-only client and
# a live delete.
#
# **`privsep=1` must be set on the token, and set FIRST.** While privilege
# separation is off, a token inherits every right of its user, and granting it
# PVEAuditor changes precisely nothing — you get a token that looks scoped in
# the UI and is still Administrator. With privsep on, effective rights are the
# intersection of user and token permissions.
#
# Do not assume it worked. The acceptance test is an actual write attempt
# through this path returning 403 — see mcpjungle/readme.md.
PROXMOX_RO_USER=op://docker/mcpjungle/PROXMOX_RO_USER
PROXMOX_RO_TOKEN_NAME=op://docker/mcpjungle/PROXMOX_RO_TOKEN_NAME
PROXMOX_RO_TOKEN_VALUE=op://docker/mcpjungle/PROXMOX_RO_TOKEN_VALUE

# Dedicated local UniFi admin without MFA — not Ubiquiti SSO credentials.
UNIFI_HOST=op://docker/mcpjungle/UNIFI_HOST
UNIFI_USERNAME=op://docker/mcpjungle/UNIFI_USERNAME
UNIFI_PASSWORD=op://docker/mcpjungle/UNIFI_PASSWORD

# Grafana. URL is the container name on the proxy network, not the Traefik
# hostname — mcpjungle sits on that network, so this skips the proxy hop and
# removes a dependency on Traefik being up. Token belongs to a Viewer-role
# service account (see readme.md), not the admin user.
GRAFANA_URL=op://docker/mcpjungle/GRAFANA_URL
GRAFANA_SERVICE_ACCOUNT_TOKEN=op://docker/mcpjungle/GRAFANA_SERVICE_ACCOUNT_TOKEN

# AdGuard Home. Same admin account adguard-sync uses (there under the `adguard`
# item as ADGUARD_USER) — AdGuard has no scoped API tokens, so there is nothing
# narrower to hand this. Copied here rather than referenced so every mcpjungle
# upstream credential stays on one item; rotating the AdGuard password means
# updating both items.
ADGUARD_URL= op://docker/mcpjungle/ADGUARD_URL
ADGUARD_USERNAME= op://docker/mcpjungle/ADGUARD_USERNAME
ADGUARD_PASSWORD= op://docker/mcpjungle/ADGUARD_PASSWORD

# NetBox. Unlike Grafana this must go through Traefik: netbox-server enforces
# ALLOWED_HOST=netbox.calzone.zone and returns 400 for a container-name Host
# header, even though it does sit on the proxy network. Token must be created
# in the NetBox UI with "Write enabled" unchecked.
NETBOX_URL=op://docker/mcpjungle/NETBOX_URL
NETBOX_TOKEN=op://docker/mcpjungle/NETBOX_TOKEN
