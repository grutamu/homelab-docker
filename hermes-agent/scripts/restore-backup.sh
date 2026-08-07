#!/bin/bash
# Restore a `hermes backup` zip into /docker-data/hermes-agent.
#
# The zip is a flat archive of ~/.hermes from a native (install.sh) install.
# Two thirds of it is runtime the Docker image already ships, and a handful of
# files are machine-local state that must not follow the agent to a new host —
# both are filtered out here. ~262 MB on disk becomes ~17 MB restored.
#
# Usage:
#   ./restore-backup.sh <backup.zip> [dest]     # dest defaults to /docker-data/hermes-agent
#
# Run with the hermes-agent container stopped. Restoring under a running
# gateway corrupts session files and the memory store.

set -euo pipefail

SRC=${1:?Usage: restore-backup.sh <backup.zip> [dest]}
DEST=${2:-/docker-data/hermes-agent}

# Matches HERMES_UID / HERMES_GID in docker-compose.yaml. The s6 stage2 hook
# remaps the container's `hermes` user to these, so the data dir must be owned
# by them or every supervised service fails on startup.
HERMES_UID=1000
HERMES_GID=1000

[ -f "$SRC" ] || { echo "No such backup: $SRC" >&2; exit 1; }

if docker ps --format '{{.Names}}' | grep -qx hermes-agent; then
    echo "hermes-agent is running. Stop it first:" >&2
    echo "  docker compose -f /root/homelab-docker/hermes-agent/docker-compose.yaml down" >&2
    exit 1
fi

if [ -e "$DEST" ] && [ -n "$(ls -A "$DEST" 2>/dev/null)" ]; then
    echo "$DEST is not empty. Move it aside first:" >&2
    echo "  mv $DEST $DEST.$(date +%Y%m%d-%H%M%S)" >&2
    exit 1
fi

mkdir -p "$DEST"

# Excluded, and why:
#
#   node/*  bin/*   A vendored Node runtime and the uv/uvx/tirith binaries,
#                   ~252 MB of the archive. The published image carries its
#                   own at /opt/hermes, which is root-owned and read-only to
#                   the runtime user. These are also host-arch binaries from
#                   a different machine.
#   *.lock          gateway.lock, auth.lock, kanban.db.*.lock,
#                   .mcp-discovery.lock — held by processes on the old host.
#                   Stale locks make the new gateway wait on an owner that
#                   will never exit.
#   processes.json  PID table from the old host. Every entry is wrong here.
#   *.bak.*         config.yaml.bak.20260802_195822 and friends.
#
# gateway_state.json is deliberately KEPT: the boot reconciler reads it to
# decide which profiles to bring up, and its last recorded state is what makes
# the gateway auto-start after a container restart.
python3 - "$SRC" "$DEST" <<'PY'
import fnmatch, os, sys, zipfile

src, dest = sys.argv[1], sys.argv[2]
SKIP = ("node/*", "bin/*", "*.lock", "processes.json", "*.bak.*")

kept = skipped = 0
with zipfile.ZipFile(src) as z:
    for info in z.infolist():
        name = info.filename
        if any(fnmatch.fnmatch(name, p) for p in SKIP):
            skipped += 1
            continue
        # Refuse absolute paths and traversal before touching the filesystem.
        target = os.path.normpath(os.path.join(dest, name))
        if not target.startswith(os.path.realpath(dest) + os.sep):
            raise SystemExit(f"unsafe path in archive: {name}")
        z.extract(info, dest)
        kept += 1

print(f"  extracted {kept} entries, skipped {skipped}")
PY

chown -R "$HERMES_UID:$HERMES_GID" "$DEST"

# .env holds credentials and the dashboard writes to it.
[ -f "$DEST/.env" ] && chmod 600 "$DEST/.env"

echo "Restored to $DEST ($(du -sh "$DEST" | cut -f1))"
echo
echo "Before starting, in $DEST/config.yaml:"
echo "  - model.base_url points at http://localhost:8020/v1 — not reachable from this host"
echo "  - mcp_servers.truenas.command is a path on the old host and holds a plaintext API key"
