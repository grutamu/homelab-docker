# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a homelab Docker Compose configuration repository managing self-hosted services on a single host. All services are organized into stacks, each with its own directory and `docker-compose.yaml`.

## Docker Host

- Hostname: `docker01` (Tailscale IP: `100.79.25.97`)
- SSH: `ssh root@docker01`
- Repo location on host: `/root/homelab-docker/`

## Secret Management

Secrets are **never committed** — they live in 1Password and are injected at deploy time via the [1Password CLI](https://developer.1password.com/docs/cli) and a local [1Password Connect](https://developer.1password.com/docs/connect) server running on `docker01` at `http://localhost:7070`.

Templates use `op://vault/item/field` syntax. The `docker` vault in 1Password holds all homelab credentials.

**Connect server credentials** are stored on `docker01` in `/etc/profile.d/1password.sh` (`OP_CONNECT_HOST`, `OP_CONNECT_TOKEN`). No interactive sign-in is required.

### Secret injection methods

| Method | Command | When to use |
|--------|---------|-------------|
| `op run` | `op run --env-file=.env.tpl -- docker compose up -d` | Stack uses `environment:` passthrough — secrets never touch disk |
| `op inject` | `op inject -i .env.tpl -o .env -f` | Stack uses `env_file:` — Docker needs a file on disk |

When creating new stacks, use the `environment:` passthrough pattern (see `backup/docker-compose.yaml`) so secrets stay in memory only.

## Deploying / Managing Services

Use `deploy.sh` — it handles `git pull`, secret injection, and `docker compose up` automatically:

```bash
# Deploy a single stack
ssh root@docker01 'bash -l -c "/root/homelab-docker/deploy.sh [stack]"'

# Deploy all stacks
ssh root@docker01 'bash -l -c "/root/homelab-docker/deploy.sh"'
```

The `bash -l` is required so `/etc/profile.d/1password.sh` is sourced (loads `OP_CONNECT_*` vars).

### Other useful commands

```bash
# Restart a single service
ssh root@docker01 'docker compose -f /root/homelab-docker/[stack]/docker-compose.yaml restart [service]'

# Pull updated images and redeploy
ssh root@docker01 'docker compose -f /root/homelab-docker/[stack]/docker-compose.yaml pull && docker compose -f /root/homelab-docker/[stack]/docker-compose.yaml up -d'

# View logs
ssh root@docker01 'docker compose -f /root/homelab-docker/[stack]/docker-compose.yaml logs -f [service]'
```

**Traefik first-time setup** (required before other stacks):
```bash
ssh root@docker01 'touch /root/homelab-docker/traefik/config/acme.json && chmod 600 /root/homelab-docker/traefik/config/acme.json'
```

## Architecture

### Networking
All services join an external Docker network called `proxy`, which is created and owned by the Traefik stack. Services that need to be reverse-proxied must connect to `proxy`. Internal service communication (e.g., app ↔ database) uses isolated internal networks defined within each stack.

### DNS
AdGuard Home runs at `192.168.99.5`. The `adguard-sync` container watches Docker events and automatically creates CNAME rewrites (`service.calzone.zone → docker-01.calzone.zone`) for any container with Traefik host labels. No manual DNS setup needed when adding new services.

### Reverse Proxy (Traefik)
Traefik handles TLS termination via Let's Encrypt with Cloudflare DNS challenge. Services expose themselves to Traefik through Docker labels:
```yaml
labels:
  - "traefik.enable=true"
  - "traefik.http.routers.[name].rule=Host(`[name].calzone.zone`)"
  - "traefik.http.routers.[name].entrypoints=https"
  - "traefik.http.routers.[name].tls=true"
  - "traefik.http.routers.[name].middlewares=pocket-id-auth@file"
  - "traefik.http.services.[name].loadbalancer.server.port=[PORT]"
```

### Storage
- **Local persistent data**: bind-mounted from `/docker-data/[stack]/`
- **Shared media/photos**: NFS mounts from TrueNAS (`truenas.calzone.zone`) at `/mnt/hdd-pool/` or `/mnt/ssd-pool/`

### Backup
Application data is backed up to TrueNAS (`/mnt/hdd-pool/backups/docker01`) via Backrest. A pre-backup hook dumps all PostgreSQL databases (immich, netbox, paperless) before each run. TrueNAS syncs the share to Backblaze B2.

### Service Stacks

| Stack | Key Services |
|-------|-------------|
| `traefik` | Traefik reverse proxy, Cloudflare tunnel |
| `monitoring` | Prometheus, Grafana, AlertManager, cAdvisor, Node Exporter |
| `mediaserver` | Plex, Radarr, Sonarr, Prowlarr, SABnzbd, Bazarr, Seerr, Recyclarr, Tautulli, Maintainerr, Watchtower |
| `immich` | Immich (photos), PostgreSQL, Redis, ML worker |
| `frigate` | Frigate NVR (Intel GPU + USB Coral accelerators) |
| `paperless` | Paperless-NGX, PostgreSQL, Redis, Gotenberg, Tika |
| `netbox` | NetBox, PostgreSQL, Redis |
| `pocket-id` | Pocket-ID OIDC provider |
| `audiobookshelf` | Audiobookshelf audiobook/podcast server |
| `mealie` | Mealie recipe manager |
| `shelfarr` | Shelfarr book request interface |
| `calibre-web` | Calibre-Web ebook library |
| `portainer` | Portainer Docker UI |
| `1password` | 1Password Connect API + Sync |
| `backup` | Backrest (Restic UI) — backs up to TrueNAS NFS |
| `adguard-sync` | Auto-creates AdGuard DNS rewrites from Docker labels |

### Conventions
- All containers use `restart: unless-stopped` (or `always`)
- User isolation: `PUID: 1000` / `PGID: 1000` (or `user: 1000:1000`)
- Localtime is bind-mounted read-only: `/etc/localtime:/etc/localtime:ro`
- Hardware passthrough: `/dev/dri` (Intel QuickSync for Frigate/Plex), `/dev/bus/usb` (Coral TPU for Frigate)
- New stacks should use `environment:` passthrough (not `env_file:`) for secret injection
