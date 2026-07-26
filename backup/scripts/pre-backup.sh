#!/bin/sh
set -e

DUMP_DIR="/source/db-dumps"
mkdir -p "$DUMP_DIR"

echo "[pre-backup] Dumping immich..."
PGPASSWORD="$IMMICH_DB_PASSWORD" pg_dump \
  -h immich_postgres -U "$IMMICH_DB_USER" immich \
  > "$DUMP_DIR/immich.sql"

echo "[pre-backup] Dumping netbox..."
PGPASSWORD="$NETBOX_DB_PASSWORD" pg_dump \
  -h netbox-postgres -U netbox netbox \
  > "$DUMP_DIR/netbox.sql"

echo "[pre-backup] Dumping paperless..."
PGPASSWORD="$PAPERLESS_DB_PASSWORD" pg_dump \
  -h paperless-db-1 -U paperless paperless \
  > "$DUMP_DIR/paperless.sql"

echo "[pre-backup] Done."
