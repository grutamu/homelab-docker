# MCPJungle's own Postgres. Create the `mcpjungle` item in the `docker` vault.
# Generate with: openssl rand -base64 32
#
# Upstream MCP server credentials are NOT here on purpose — every stdio server
# spawned by MCPJungle inherits this container's environment, so a token placed
# here would be readable by all of them. They go in per-server instead, at
# registration time via .env.register.tpl. See readme.md.
POSTGRES_PASSWORD=op://docker/mcpjungle/POSTGRES_PASSWORD
