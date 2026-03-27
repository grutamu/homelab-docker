# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a homelab Docker Compose configuration repository managing self-hosted services on a single host. All services are organized into stacks, each with its own directory and `docker-compose.yaml`.

## Secret Management

Secrets are **never committed** — they live in 1Password and are injected via the 1Password CLI.

**Inject all secrets at once:**
```bash
./decrypt.sh
```
This runs `op inject` for every `.env.tpl` / `config.yml.tpl` template, producing the actual `.env` / config files used by Docker Compose. Requires `op` (1Password CLI) to be installed and authenticated.

**Inject secrets for a single stack:**
```bash
eval $(op signin)
op inject -i ./[stack]/.env.tpl -o ./[stack]/.env -f
```

Templates use `op://vault/item/field` syntax. The generated files (`.env`, `config.yml`) are gitignored.

## Deploying / Managing Services

All operations are performed per-stack from the repo root:

```bash
# Start a stack
docker compose -f [stack]/docker-compose.yaml up -d

# Restart a single service within a stack
docker compose -f [stack]/docker-compose.yaml restart [service]

# Pull updated images and redeploy
docker compose -f [stack]/docker-compose.yaml pull && docker compose -f [stack]/docker-compose.yaml up -d

# View logs
docker compose -f [stack]/docker-compose.yaml logs -f [service]
```

**Traefik first-time setup** (required before other stacks):
```bash
touch ./traefik/config/acme.json
chmod 600 ./traefik/config/acme.json
```

## Architecture

### Networking
All services join an external Docker network called `proxy`, which is created and owned by the Traefik stack. Services that need to be reverse-proxied must connect to `proxy`. Internal service communication (e.g., app ↔ database) uses isolated internal networks defined within each stack.

### Reverse Proxy (Traefik)
Traefik handles TLS termination via Let's Encrypt with Cloudflare DNS challenge. Services expose themselves to Traefik through Docker labels:
```yaml
labels:
  - "traefik.enable=true"
  - "traefik.http.routers.[name].rule=Host(`[name].calzone.zone`)"
  - "traefik.http.routers.[name].entrypoints=https"
  - "traefik.http.routers.[name].tls=true"
  - "traefik.http.services.[name].loadbalancer.server.port=[PORT]"
```

### Storage
- **Local persistent data**: bind-mounted from `/docker-data/[stack]/`
- **Shared media/photos**: NFS mounts from TrueNAS (`truenas.calzone.zone`) at `/mnt/ssd-pool/`

### Service Stacks

| Stack | Key Services |
|-------|-------------|
| `traefik` | Traefik reverse proxy, Cloudflare tunnel |
| `monitoring` | Prometheus, Grafana, AlertManager, cAdvisor, Node Exporter |
| `mediaserver` | Plex, Radarr, Sonarr, Prowlarr, Bazarr, Seerr, Recyclarr, Tautulli, Maintainerr, Watchtower |
| `immich` | Immich (photos), PostgreSQL, Redis, ML worker |
| `frigate` | Frigate NVR (Intel GPU + USB Coral accelerators) |
| `paperless` | Paperless-NGX, PostgreSQL, Redis, Gotenberg, Tika |
| `netbox` | NetBox, PostgreSQL, Redis |
| `pocket-id` | Pocket-ID OIDC provider |
| `audiobookshelf` | Audiobookshelf audiobook/podcast server |
| `mealie` | Mealie recipe manager |
| `portainer` | Portainer Docker UI |
| `1password` | 1Password Connect API + Sync |

### Conventions
- All containers use `restart: unless-stopped` (or `always`)
- User isolation: `PUID: 1000` / `PGID: 1000` (or `user: 1000:1000`)
- Localtime is bind-mounted read-only: `/etc/localtime:/etc/localtime:ro`
- Hardware passthrough: `/dev/dri` (Intel QuickSync for Frigate/Plex), `/dev/bus/usb` (Coral TPU for Frigate)
