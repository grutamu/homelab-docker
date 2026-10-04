# Upstream MCP server credentials, from the `mcp-servers` item in the `docker`
# vault. Injected by deploy.sh via `op run`; compose interpolates each value
# into only the container that needs it, so no server sees another's secrets.
#
# Hosts and usernames are in 1Password alongside the tokens, not committed —
# this repo never records where the backends actually live.

# Grafana — Viewer-role service account (scripts/grafana-service-account.sh).
GRAFANA_URL=op://docker/mcp-servers/GRAFANA_URL
GRAFANA_SERVICE_ACCOUNT_TOKEN=op://docker/mcp-servers/GRAFANA_SERVICE_ACCOUNT_TOKEN

# NetBox — read-only token.
NETBOX_URL=op://docker/mcp-servers/NETBOX_URL
NETBOX_TOKEN=op://docker/mcp-servers/NETBOX_TOKEN

# Proxmox — the privsep=1 PVEAuditor token. Host/port are shared with the
# full-admin token, which stays in the item but is not served.
PROXMOX_HOST=op://docker/mcp-servers/PROXMOX_HOST
PROXMOX_PORT=op://docker/mcp-servers/PROXMOX_PORT
PROXMOX_RO_USER=op://docker/mcp-servers/PROXMOX_RO_USER
PROXMOX_RO_TOKEN_NAME=op://docker/mcp-servers/PROXMOX_RO_TOKEN_NAME
PROXMOX_RO_TOKEN_VALUE=op://docker/mcp-servers/PROXMOX_RO_TOKEN_VALUE

# Home Assistant — long-lived token from the HA user profile page.
HOMEASSISTANT_URL=op://docker/mcp-servers/HOMEASSISTANT_URL
HOMEASSISTANT_TOKEN=op://docker/mcp-servers/HOMEASSISTANT_TOKEN

# UniFi — dedicated local admin without MFA.
UNIFI_HOST=op://docker/mcp-servers/UNIFI_HOST
UNIFI_USERNAME=op://docker/mcp-servers/UNIFI_USERNAME
UNIFI_PASSWORD=op://docker/mcp-servers/UNIFI_PASSWORD

# AdGuard Home — the admin account (no scoped tokens exist). Also on the
# `adguard` item for adguard-sync; rotating it means updating both.
ADGUARD_URL=op://docker/mcp-servers/ADGUARD_URL
ADGUARD_USERNAME=op://docker/mcp-servers/ADGUARD_USERNAME
ADGUARD_PASSWORD=op://docker/mcp-servers/ADGUARD_PASSWORD

# What the portal presents to each server. The same values are stored on the
# portal's server definitions; rotating one means updating both (see readme.md).
GRAFANA_MCP_AUTH_TOKEN=op://docker/mcp-servers/GRAFANA_MCP_AUTH_TOKEN
NETBOX_MCP_AUTH_TOKEN=op://docker/mcp-servers/NETBOX_MCP_AUTH_TOKEN
PROXMOX_RO_MCP_API_KEY=op://docker/mcp-servers/PROXMOX_RO_MCP_API_KEY
HA_MCP_SECRET_PATH=op://docker/mcp-servers/HA_MCP_SECRET_PATH
