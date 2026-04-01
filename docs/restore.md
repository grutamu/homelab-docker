# Restore Procedures

Backups are managed by Backrest (Restic) and stored on TrueNAS at `/mnt/hdd-pool/backups/docker01`, which syncs to Backblaze B2. The Backrest UI is available at `backrest.calzone.zone`.

---

## 1. Restore a file or directory (Backrest UI)

Use this when you need to recover specific files (e.g., a single service's config).

1. Open `backrest.calzone.zone`
2. Select your repo → **Snapshots**
3. Find the snapshot you want (filter by date)
4. Click **Restore** → browse to the path you need
5. Set the restore target (e.g., `/source/paperless` to restore in-place)
6. Click **Restore**

---

## 2. Restore a PostgreSQL database

Database dumps are written to `/docker-data/db-dumps/` before each backup and are included in every snapshot as `/source/db-dumps/`.

### Step 1 — Restore the dump file from Backrest

In the Backrest UI, restore the specific dump file from the snapshot:

- `Snapshot → /source/db-dumps/immich.sql` → restore to `/tmp/immich.sql`
- `Snapshot → /source/db-dumps/netbox.sql` → restore to `/tmp/netbox.sql`
- `Snapshot → /source/db-dumps/paperless.sql` → restore to `/tmp/paperless.sql`

### Step 2 — Load the dump into the running container

```bash
ssh root@docker01

# Immich
docker exec -i immich_postgres psql -U postgres immich < /tmp/immich.sql

# NetBox
docker exec -e PGPASSWORD=<password> -i netbox-postgres psql -U netbox netbox < /tmp/netbox.sql

# Paperless
docker exec -i paperless-db-1 psql -U paperless paperless < /tmp/paperless.sql
```

> **Note:** Stop the app container before restoring its database to avoid conflicts:
> ```bash
> docker compose -f /root/homelab-docker/[stack]/docker-compose.yaml stop [app-service]
> # restore database...
> docker compose -f /root/homelab-docker/[stack]/docker-compose.yaml start [app-service]
> ```

---

## 3. Restore a full stack

Use this when a service's data directory is corrupted or accidentally deleted.

### Step 1 — Stop the stack

```bash
ssh root@docker01 'docker compose -f /root/homelab-docker/[stack]/docker-compose.yaml down'
```

### Step 2 — Restore data from Backrest

In the Backrest UI, restore the stack's data directory from a snapshot:

- Source path in snapshot: `/source/[stack]/`
- Restore target: `/source/[stack]/` (restores to `/docker-data/[stack]/` on the host)

### Step 3 — Redeploy

```bash
ssh root@docker01 'bash -l -c "/root/homelab-docker/deploy.sh [stack]"'
```

---

## 4. Full disaster recovery (docker01 rebuild)

Use this if docker01 itself needs to be rebuilt from scratch.

### Prerequisites
- TrueNAS is still running (backup share intact)
- Access to 1Password
- A fresh Ubuntu host named `docker01` on `192.168.99.41` with Tailscale installed

### Step 1 — Install dependencies on the new host

```bash
ssh root@docker01

# Docker
curl -fsSL https://get.docker.com | sh

# 1Password CLI
curl -sS https://downloads.1password.com/linux/keys/1password.asc | gpg --dearmor -o /usr/share/keyrings/1password-archive-keyring.gpg
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/amd64 stable main" > /etc/apt/sources.list.d/1password.list
apt update && apt install -y 1password-cli
```

### Step 2 — Clone the repo

```bash
git clone https://github.com/grutamu/homelab-docker.git /root/homelab-docker
```

### Step 3 — Restore 1Password Connect

```bash
# Copy credentials file from your local machine
scp ~/path/to/1password-credentials.json root@docker01:/root/homelab-docker/1password/

# Deploy Connect
docker compose -f /root/homelab-docker/1password/docker-compose.yaml up -d

# Set Connect env vars (get token from 1password.com → Integrations)
echo 'export OP_CONNECT_HOST=http://localhost:7070' >> /etc/profile.d/1password.sh
echo 'export OP_CONNECT_TOKEN=<token>' >> /etc/profile.d/1password.sh
chmod +x /etc/profile.d/1password.sh
source /etc/profile.d/1password.sh
```

### Step 4 — Create the proxy network

```bash
docker network create proxy
```

### Step 5 — Restore /docker-data from Backrest

Install Restic directly to restore without Backrest running:

```bash
apt install -y restic

# Mount the backup share temporarily
mkdir -p /mnt/restore
mount -t nfs truenas.calzone.zone:/mnt/hdd-pool/backups/docker01 /mnt/restore

# List snapshots
RESTIC_PASSWORD=<password> restic -r /mnt/restore snapshots

# Restore the latest snapshot to /
RESTIC_PASSWORD=<password> restic -r /mnt/restore restore latest --target / --include /docker-data

umount /mnt/restore
```

### Step 6 — Restore databases

The dump files will be at `/docker-data/db-dumps/` after the restore. Deploy the database containers first, then load the dumps:

```bash
bash -l -c "/root/homelab-docker/deploy.sh immich"
docker exec -i immich_postgres psql -U postgres immich < /docker-data/db-dumps/immich.sql

bash -l -c "/root/homelab-docker/deploy.sh netbox"
docker exec -i netbox-postgres psql -U netbox netbox < /docker-data/db-dumps/netbox.sql

bash -l -c "/root/homelab-docker/deploy.sh paperless"
docker exec -i paperless-db-1 psql -U paperless paperless < /docker-data/db-dumps/paperless.sql
```

### Step 7 — Deploy all remaining stacks

```bash
bash -l -c "/root/homelab-docker/deploy.sh"
```

---

## Reference

| What | Where |
|------|-------|
| Backup UI | `backrest.calzone.zone` |
| Backup destination (local) | `truenas.calzone.zone:/mnt/hdd-pool/backups/docker01` |
| Backup destination (cloud) | Backblaze B2 (synced by TrueNAS) |
| DB dumps (in snapshots) | `/source/db-dumps/` |
| App data (in snapshots) | `/source/[stack]/` |
| Restic repo password | `op://docker/backrest/RESTIC_PASSWORD` |
