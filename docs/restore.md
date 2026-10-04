# Restore Procedures

## Backup Strategy Overview

docker-01 has two independent backup layers:

| Layer | Tool | Schedule | Destination | Retention | Best for |
|-------|------|----------|-------------|-----------|----------|
| VM snapshot | Proxmox | Nightly 21:00 | TrueNAS → Backblaze B2 | 7 daily, 12 monthly, 1 yearly | Full VM recovery, disaster recovery |
| File-level | Backrest (Restic) | Nightly 03:00 | TrueNAS → Backblaze B2 | 7 daily, 4 weekly, 6 monthly | Granular file/DB restore without touching the VM |

**Primary recovery path is always Proxmox.** Backrest exists for fast granular restores — recovering a single service or database without the overhead of a full VM restore.

> **Note:** NFS-mounted data (Immich photos, Paperless documents, media) lives on TrueNAS directly and is not on docker-01's disk. TrueNAS manages its own backups for those datasets.

---

## 1. Restore a file or directory (Backrest — fastest)

Use when you need to recover a specific file or service data directory without a full VM restore.

1. Open `backrest.calzone.zone`
2. Select your repo → **Snapshots**
3. Find the snapshot by date
4. Click **Restore** → browse to the path (e.g., `/source/paperless`)
5. Set restore target and click **Restore**

---

## 2. Restore a PostgreSQL database (Backrest)

Database dumps are written to `/docker-data/db-dumps/` before each backup and are included in every snapshot as `/source/db-dumps/`.

### Step 1 — Restore the dump file from Backrest UI

Restore the specific `.sql` file from a snapshot to `/tmp/` on docker-01.

### Step 2 — Load the dump into the running container

```bash
ssh root@docker01

# Stop the app (not the database) to avoid conflicts
docker compose -f /root/homelab-docker/[stack]/docker-compose.yaml stop [app-service]

# Immich
docker exec -i immich_postgres psql -U postgres immich < /tmp/immich.sql

# NetBox
docker exec -i netbox-postgres psql -U netbox netbox < /tmp/netbox.sql

# Paperless
docker exec -i paperless-db-1 psql -U paperless paperless < /tmp/paperless.sql

# Restart the app
docker compose -f /root/homelab-docker/[stack]/docker-compose.yaml start [app-service]
```

---

## 3. Full VM restore (Proxmox — disaster recovery)

Use when docker-01 itself needs to be recovered. This restores the entire VM to a known-good state.

1. In Proxmox: **Storage (truenas) → Backups**
2. Find the `vzdump-qemu-102-*.vma.zst` backup to restore from
3. Click **Restore** → select target node → **Restore**
4. Once booted, redeploy any stacks that were updated after the backup timestamp:
   ```bash
   ssh root@docker01 'bash -l -c "cd /root/homelab-docker && git pull && ./deploy.sh [stack]"'
   ```

> The Proxmox backup captures everything on docker-01's disk including `/docker-data/`, Docker itself, and all configs. A full restore brings the VM back to its exact state at backup time.

---

## 4. Full rebuild from scratch

Use only if the Proxmox backup is also unavailable (e.g., both local and B2 copies lost). See the Backrest restore path in this case.

### Step 1 — Restore VM backup from Backblaze B2

TrueNAS syncs Proxmox backups to B2. Download the latest `vzdump-qemu-102-*.vma.zst` from B2, copy to TrueNAS, then restore via Proxmox as above.

### Step 2 — If VM backup is unrecoverable, rebuild manually

```bash
# On a fresh Ubuntu host

# Install Docker
curl -fsSL https://get.docker.com | sh

# Install 1Password CLI
curl -sS https://downloads.1password.com/linux/keys/1password.asc | gpg --dearmor -o /usr/share/keyrings/1password-archive-keyring.gpg
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/amd64 stable main" > /etc/apt/sources.list.d/1password.list
apt update && apt install -y 1password-cli restic

# Clone repo
git clone https://github.com/grutamu/homelab-docker.git /root/homelab-docker

# Restore 1Password Connect (copy 1password-credentials.json from local machine)
scp ~/path/to/1password-credentials.json root@docker01:/root/homelab-docker/1password/
docker compose -f /root/homelab-docker/1password/docker-compose.yaml up -d

# Set Connect credentials
cat >> /etc/profile.d/1password.sh << 'EOF'
export OP_CONNECT_HOST=http://localhost:7070
export OP_CONNECT_TOKEN=<token from 1password.com → Integrations>
EOF
chmod +x /etc/profile.d/1password.sh && source /etc/profile.d/1password.sh

# Create proxy network
docker network create proxy

# Restore /docker-data from Backrest repo on TrueNAS
mkdir -p /mnt/restore
mount -t nfs truenas.calzone.zone:/mnt/hdd-pool/backups/docker01 /mnt/restore
RESTIC_PASSWORD=$(op read op://docker/backrest/RESTIC_PASSWORD) restic -r /mnt/restore restore latest --target / --include /docker-data
umount /mnt/restore

# Restore databases from dumps
bash -l -c "/root/homelab-docker/deploy.sh immich"
docker exec -i immich_postgres psql -U postgres immich < /docker-data/db-dumps/immich.sql

bash -l -c "/root/homelab-docker/deploy.sh netbox"
docker exec -i netbox-postgres psql -U netbox netbox < /docker-data/db-dumps/netbox.sql

bash -l -c "/root/homelab-docker/deploy.sh paperless"
docker exec -i paperless-db-1 psql -U paperless paperless < /docker-data/db-dumps/paperless.sql

# Deploy everything
bash -l -c "/root/homelab-docker/deploy.sh"
```

---

## Reference

| What | Where |
|------|-------|
| Proxmox backups | Proxmox UI → Storage (truenas) → Backups → VM 102 (docker-01) |
| Backrest UI | `backrest.calzone.zone` |
| Restic repo | `truenas.calzone.zone:/mnt/hdd-pool/backups/docker01` |
| Restic password | `op://docker/backrest/RESTIC_PASSWORD` |
| B2 offsite (Proxmox VMs) | Synced by TrueNAS |
| B2 offsite (Restic repo) | Synced by TrueNAS |
| DB dumps (in Restic snapshots) | `/source/db-dumps/` |
