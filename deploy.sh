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
#   ./deploy.sh --list       # print the stack list, one per line, and exit
#
# Requires OP_CONNECT_HOST and OP_CONNECT_TOKEN to be set (see /etc/profile.d/1password.sh).

set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"

# Every stack that runs on docker01, in deploy order. This is the single source
# of truth for "deployable here" — CI reads it via --list. A stack directory
# absent from this list is never deployed by automation:
#   github-runner  deploying it would restart the runner mid-job
#   docs           not a stack
# Order matters: backup attaches to other stacks' Docker networks as external,
# so it must come after them.
STACKS=(traefik infra monitoring pocket-id 1password
        mediaserver immich paperless frigate netbox
        audiobookshelf mealie portainer shelfarr
        minio mcpjungle hermes-agent backup adguard-sync)

if [ "${1:-}" = "--list" ]; then
    printf '%s\n' "${STACKS[@]}"
    exit 0
fi

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
    elif [ "$stack" = "mediaserver" ]; then
        op inject -i "$REPO/mediaserver/recyclarr/recyclarr.yml.tpl" \
                  -o "$REPO/mediaserver/recyclarr/recyclarr.yml" -f
        # recyclarr runs as uid 1000; op inject writes 0600 root, so hand
        # the resolved config to the container user (still not world-readable)
        chown 1000:1000 "$REPO/mediaserver/recyclarr/recyclarr.yml"
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
    for stack in "${STACKS[@]}"; do
        deploy "$stack"
    done
fi

echo ""
echo "Done."
