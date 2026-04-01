#!/bin/bash
# Deploy one or all stacks with secrets injected from 1Password Connect.
#
# Secrets are injected at runtime via op run (no files written to disk).
# Frigate is the only exception: its config.yml must be written to disk
# because Frigate reads it directly as a file (not as environment variables).
#
# Usage:
#   ./deploy.sh              # pull latest and deploy all stacks
#   ./deploy.sh <stack>      # pull latest and deploy one stack
#
# Requires OP_CONNECT_HOST and OP_CONNECT_TOKEN to be set (see /etc/profile.d/1password.sh).

set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"

deploy() {
    local stack=$1
    local compose="$REPO/$stack/docker-compose.yaml"
    local env_tpl="$REPO/$stack/.env.tpl"

    [ -f "$compose" ] || { echo "No compose file for '$stack', skipping."; return; }

    echo "==> $stack"

    if [ "$stack" = "frigate" ]; then
        op inject -i "$REPO/frigate/config/config.yml.tpl" \
                  -o "$REPO/frigate/config/config.yml" -f
        docker compose -f "$compose" up -d
    elif [ -f "$env_tpl" ]; then
        op run --env-file="$env_tpl" -- docker compose -f "$compose" up -d
    else
        docker compose -f "$compose" up -d
    fi
}

cd "$REPO"
git pull

if [ $# -eq 1 ]; then
    deploy "$1"
else
    for stack in traefik monitoring pocket-id 1password \
                 mediaserver immich paperless frigate netbox \
                 audiobookshelf mealie portainer shelfarr \
                 calibre-web backup adguard-sync; do
        deploy "$stack"
    done
fi

echo ""
echo "Done."
