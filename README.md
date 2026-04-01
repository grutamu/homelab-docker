# homelab-docker

Docker Compose configurations for a self-hosted homelab. Each service is organized into its own stack directory.

## Services

### Infrastructure
| Service | Description |
|---------|-------------|
| [Traefik](https://traefik.io) | Reverse proxy and TLS termination via Let's Encrypt + Cloudflare DNS |
| [Portainer](https://portainer.io) | Docker management UI |
| [1Password Connect](https://developer.1password.com/docs/connect) | Local secrets API — serves credentials to `op` CLI at deploy time |
| [AdGuard Home](https://adguard.com/en/adguard-home/overview.html) | DNS server with ad blocking (`192.168.99.5`) |
| [adguard-sync](./adguard-sync/) | Watches Docker events and auto-creates AdGuard CNAME rewrites for Traefik-labelled containers |

### Authentication
| Service | Description |
|---------|-------------|
| [Pocket ID](https://github.com/stonith404/pocket-id) | Self-hosted OIDC provider — SSO for all internal services |

### Monitoring
| Service | Description |
|---------|-------------|
| [Prometheus](https://prometheus.io) | Metrics collection |
| [Grafana](https://grafana.com) | Metrics visualization |
| [AlertManager](https://prometheus.io/docs/alerting/latest/alertmanager/) | Alerting |
| [cAdvisor](https://github.com/google/cadvisor) | Container resource metrics |
| [Node Exporter](https://github.com/prometheus/node_exporter) | Host system metrics |

### Media
| Service | Description |
|---------|-------------|
| [Plex](https://plex.tv) | Media server |
| [Radarr](https://radarr.video) | Movie library management |
| [Sonarr](https://sonarr.tv) | TV series library management |
| [Prowlarr](https://github.com/Prowlarr/Prowlarr) | Indexer manager for the *arr suite |
| [SABnzbd](https://sabnzbd.org) | Usenet download client |
| [Bazarr](https://bazarr.media) | Subtitle management |
| [Seerr](https://github.com/seerr-team/seerr) | Media request interface |
| [Shelfarr](https://github.com/pedro-revez-silva/shelfarr) | Book request interface |
| [Recyclarr](https://recyclarr.dev) | Sync TRaSH Guide quality profiles to Radarr/Sonarr |
| [Tautulli](https://tautulli.com) | Plex analytics |
| [Maintainerr](https://github.com/jorenn92/Maintainerr) | Automated media collection cleanup |
| [Watchtower](https://containrrr.dev/watchtower) | Automatic container image updates |
| [Audiobookshelf](https://audiobookshelf.org) | Audiobook and podcast server |
| [Calibre-Web](https://github.com/janeczku/calibre-web) | Ebook library management and reader |

### Surveillance
| Service | Description |
|---------|-------------|
| [Frigate](https://frigate.video) | NVR with hardware-accelerated object detection (Intel GPU + Coral TPU) |

### Photos
| Service | Description |
|---------|-------------|
| [Immich](https://immich.app) | Self-hosted photo and video library |

### Documents & Data
| Service | Description |
|---------|-------------|
| [Paperless-NGX](https://docs.paperless-ngx.com) | Document scanning and archival |
| [Mealie](https://mealie.io) | Recipe management |
| [NetBox](https://netbox.dev) | Network documentation and IPAM |

### Backup
| Service | Description |
|---------|-------------|
| [Backrest](https://github.com/garethgeorge/backrest) | Restic backup UI — backs up `/docker-data/` to TrueNAS NFS share nightly |

---

## Secret Management

Secrets are stored in 1Password and never committed to this repository. The [1Password Connect](https://developer.1password.com/docs/connect) server runs locally on `docker01` (`http://localhost:7070`) and serves as the secrets API — no interactive sign-in required at deploy time.

Template files (`.env.tpl`, `config.yml.tpl`) contain `op://` references in place of secret values:

```
DB_PASSWORD=op://docker/immich/DB_PASSWORD
```

### How secrets are injected

There are two injection methods depending on how each stack is structured:

| Method | When used | How |
|--------|-----------|-----|
| `op run` | Stack uses `environment:` passthrough — secrets stay in memory only | `op run --env-file=.env.tpl -- docker compose up -d` |
| `op inject` | Stack uses `env_file:` — Docker needs a file on disk to inject into containers | `op inject -i .env.tpl -o .env -f` |

When adding a new stack, prefer the `environment:` passthrough pattern (see `backup/docker-compose.yaml`) so secrets are never written to disk.

---

## Deployment

The Docker host is `docker01` (`100.79.25.97`), accessible via Tailscale SSH:

```bash
ssh root@docker01
```

### Deploying a change

Commit and push locally, then run `deploy.sh` on docker01. It handles `git pull`, secret injection, and `docker compose up` in one step:

```bash
# Deploy a single stack
ssh root@docker01 'bash -l -c "/root/homelab-docker/deploy.sh [stack]"'

# Deploy all stacks
ssh root@docker01 'bash -l -c "/root/homelab-docker/deploy.sh"'
```

### DNS

All services are accessed at `[service].calzone.zone` over HTTPS. DNS rewrites are managed automatically by the `adguard-sync` container — when a container with Traefik labels starts, a CNAME rewrite (`service.calzone.zone → docker-01.calzone.zone`) is created in AdGuard Home automatically. No manual DNS configuration needed when adding new services.

### Viewing logs

```bash
ssh root@docker01 'docker compose -f /root/homelab-docker/[stack]/docker-compose.yaml logs -f [service]'
```

---

## Networking

All services join an external Docker network called `proxy`, owned by the Traefik stack. Persistent data is stored in `/docker-data/[stack]/` on the host. Shared media is served from TrueNAS over NFS at `truenas.calzone.zone`.

---

## Backup

Application data in `/docker-data/` is backed up to TrueNAS (`/mnt/hdd-pool/backups/docker01`) via Backrest (Restic). Before each backup, a pre-backup hook dumps all PostgreSQL databases:

| Database | Container |
|----------|-----------|
| `immich` | `immich_postgres` |
| `netbox` | `netbox-postgres` |
| `paperless` | `paperless-db-1` |

TrueNAS then syncs the backup share to Backblaze B2. Plex is excluded from backups (rebuilable metadata).
