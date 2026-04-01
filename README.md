# homelab-docker

Docker Compose configurations for a self-hosted homelab. Each service is organized into its own stack directory.

## Services

### Infrastructure
| Service | Description |
|---------|-------------|
| [Traefik](https://traefik.io) | Reverse proxy and TLS termination via Let's Encrypt + Cloudflare DNS |
| [Portainer](https://portainer.io) | Docker management UI |
| [1Password Connect](https://developer.1password.com/docs/connect) | Local secrets API used for injecting credentials |

### Authentication
| Service | Description |
|---------|-------------|
| [Pocket ID](https://github.com/stonith404/pocket-id) | Self-hosted OIDC provider |

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

---

## Secret Management

Secrets are stored in 1Password and never committed to this repository. `.env` files and sensitive config files are generated locally from `.tpl` templates using the [1Password CLI](https://developer.1password.com/docs/cli).

### Injecting all secrets

Run the decrypt script from the repo root. It will prompt you to authenticate with 1Password and then populate all secrets across every stack:

```bash
./decrypt.sh
```

### Injecting secrets for a single stack

```bash
eval $(op signin)
op inject -i ./[stack]/.env.tpl -o ./[stack]/.env -f
```

### How it works

Template files (`.env.tpl`, `config.yml.tpl`) contain `op://` references in place of secret values:

```
CF_DNS_API_TOKEN=op://docker/traefik/CF_DNS_API_TOKEN
```

`op inject` resolves each reference against your 1Password vault and writes the populated file. The generated files are gitignored.

---

## Networking

All services are exposed through Traefik via an external Docker network called `proxy`. Services are accessed at `[service].calzone.zone` over HTTPS.

Persistent data is stored in `/docker-data/[stack]/` on the host. Shared media is served from TrueNAS over NFS at `truenas.calzone.zone`.

---

## Deployment

The Docker host is `docker01` (`100.79.25.97`), accessible via Tailscale SSH:

```bash
ssh root@100.79.25.97
```

### Deploying a change

1. Commit and push changes from your local machine
2. Pull the updated config on the host:
   ```bash
   ssh root@100.79.25.97 'cd /root/homelab-docker && git pull'
   ```
3. Redeploy the affected stack:
   ```bash
   ssh root@100.79.25.97 'cd /root/homelab-docker && docker compose -f [stack]/docker-compose.yaml up -d'
   ```

### Starting a new stack for the first time

```bash
ssh root@100.79.25.97 'cd /root/homelab-docker && docker compose -f [stack]/docker-compose.yaml up -d'
```

### Viewing logs

```bash
ssh root@100.79.25.97 'cd /root/homelab-docker && docker compose -f [stack]/docker-compose.yaml logs -f [service]'
```
