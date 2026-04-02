# TODO

## Secret Management

- [x] **Remove `decrypt.sh`** — Superseded by `deploy.sh`. Delete the file and remove references from docs.

- [x] **Migrate remaining stacks to `environment:` passthrough** — All stacks now use `op run` for secret injection. `deploy.sh` simplified to a single code path (frigate remains an exception — its config.yml must be written to disk). Consolidated netbox's 3 `.env.tpl` files into one.

## Backup

- [ ] **Add missing 1Password entries** — Required before `./deploy.sh backup` works cleanly:
  - `op://docker/paperless/POSTGRES_PASSWORD`
  - `op://docker/backrest/RESTIC_PASSWORD`

- [ ] **Configure TrueNAS to sync backup share to Backblaze B2** — The Restic repo at `/mnt/hdd-pool/backups/docker01` needs a B2 sync job in TrueNAS (same as the Proxmox VM backup sync).

- [ ] **Test a restore** — Verify the backup actually works before you need it. Restore a single file via Backrest UI and confirm a `pg_dump` loads cleanly into a test database.

## Monitoring

- [x] **Fix AlertManager configuration** — Replaced email placeholder with Discord webhook via alertmanager-discord bridge. Alerts routing to Discord.

- [ ] **Add blackbox_exporter for HTTP uptime monitoring** — Add HTTP probes for key services (Immich, Paperless, Plex, NetBox, etc.) so a container serving 502s is caught. Add scrape job and alert rules for probe failures.

- [x] **Scrape Traefik Prometheus metrics** — Enabled `metrics: prometheus: {}` in traefik.yml, added scrape job targeting `traefik:8080`.

- [ ] **Add postgres_exporter for database monitoring** — Cover the 3 PostgreSQL instances (immich, netbox, paperless). Surface connection pool exhaustion, slow queries, dead tuples. Credentials via 1Password.

- [x] **Add NFS mount health alert** — NFSMountError alert using `node_filesystem_device_error{fstype=~"nfs4?"}` on Docker volume mount points.

- [ ] **Add severity-based alert routing** — Configure separate AlertManager routes for `critical` vs `warning`. Critical alerts (disk full, container down) page immediately; warnings can be batched.

- [x] **Fix ContainerRestarting alert expression** — Switched to `increase(container_restart_count[15m]) > 0`.

- [x] **Add "container absent" alerts for critical services** — CriticalContainerDown alert using `absent(container_last_seen{name="..."})` for traefik, prometheus, grafana, immich_server, paperless-ngx, netbox.

- [ ] **Add Loki + Promtail for log aggregation** — Ship Docker logs into Grafana via Loki. Completes metrics+logs observability. Configure Loki as a Grafana datasource.

- [ ] **Add backup freshness alert** — Alert if last successful Backrest backup is older than 24h. Options: cron script exposing a Prometheus metric, or Backrest webhook updating a heartbeat endpoint.

- [x] **Configure Grafana SSO via Pocket-ID OIDC** — Configured via Grafana UI. Scopes: openid, email, profile. API URL: https://auth.calzone.zone/api/oidc/userinfo.

## Docker Deployment Improvements

- [ ] **Pin image versions** — Replace `:latest` tags with specific versions (e.g. `radarr:5.14.0`). Keeps a known-good version in git for rollbacks. Watchtower will still handle updates.

- [ ] **Control Watchtower scope** — Run Watchtower with `--label-enable` so updates are opt-in. Add `com.centurylinklabs.watchtower.enable=true` to services you want updated, and keep databases/stateful services out.

- [ ] **Move Watchtower and cf-tunnel out of `mediaserver`** — Both are infrastructure. Move to the `traefik` stack or a dedicated `infra` stack.

- [ ] **Add healthchecks to databases and use `condition: service_healthy`** — Postgres and Redis containers lack healthchecks, so `depends_on` doesn't actually wait for readiness. Add `pg_isready` / `redis-cli ping` healthchecks and update `depends_on` conditions.

- [ ] **Remove redundant `TZ` env vars** — `/etc/localtime` is already bind-mounted on most services. Pick one approach and apply it consistently.

## Done

- [x] **Add a task runner** — `deploy.sh` handles `git pull` + secret injection + `docker compose up` in one command for any stack.
- [x] **Set up 1Password Connect** — Running on docker01 at `http://localhost:7070`. Credentials in `/etc/profile.d/1password.sh`.
- [x] **Runtime secret injection** — `deploy.sh` uses `op run` (no files on disk) for new stacks and `op inject` for legacy stacks with `env_file:`.
- [x] **Automatic DNS rewrites** — `adguard-sync` watches Docker events and creates AdGuard CNAME rewrites automatically for any Traefik-labelled container.
- [x] **Backup stack** — Backrest running at `backrest.calzone.zone`. Pre-backup hooks dump immich, netbox, and paperless postgres. NFS destination on TrueNAS.
- [x] **Replace Traefik basic auth with Pocket-ID SSO** — `pocket-id-auth@file` middleware applied to all internal services.
- [x] **Document restore procedures** — `docs/restore.md` covers Backrest granular restore and Proxmox VM restore.
