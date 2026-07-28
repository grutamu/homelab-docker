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
