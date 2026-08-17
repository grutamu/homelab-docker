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

echo "[pre-backup] Dumping mcpjungle..."
PGPASSWORD="$MCPJUNGLE_DB_PASSWORD" pg_dump \
  -h mcpjungle-postgres -U mcpjungle mcpjungle \
  > "$DUMP_DIR/mcpjungle.sql"

# MariaDB, not postgres — grimmory is the only stack on it. The raw data dir
# under /docker-data/grimmory/mariadb is swept by the file-level backup too,
# but a live InnoDB dir copied mid-write is not guaranteed restorable; this
# dump is the consistent copy.
echo "[pre-backup] Dumping grimmory..."
mariadb-dump --single-transaction \
  -h grimmory-mariadb -u grimmory -p"$GRIMMORY_DB_PASSWORD" grimmory \
  > "$DUMP_DIR/grimmory.sql"

echo "[pre-backup] Done."
