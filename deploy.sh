#!/bin/bash
# Deploy one or all stacks with secrets injected at runtime from 1Password Connect.
# No .env files are written to disk — secrets live only in the process environment.
#
# Usage:
#   ./deploy.sh              # pull latest and deploy all stacks
#   ./deploy.sh <stack>      # pull latest and deploy one stack
#
# Requires OP_CONNECT_HOST and OP_CONNECT_TOKEN to be set (see /etc/profile.d/1password.sh).

set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"

_op_run() {
    local env_tpl=$1; shift
    op run --env-file="$env_tpl" -- "$@"
}

deploy() {
    local stack=$1
    local compose="$REPO/$stack/docker-compose.yaml"
    local env_tpl="$REPO/$stack/.env.tpl"

    [ -f "$compose" ] || { echo "No compose file for '$stack', skipping."; return; }

    echo "==> $stack"

    case "$stack" in
        frigate)
            # Config file template — must be injected as a file
            op inject -i "$REPO/frigate/config/config.yml.tpl" \
                      -o "$REPO/frigate/config/config.yml" -f
            docker compose -f "$compose" up -d
            ;;
        netbox)
            # Three config file templates
            op inject -i "$REPO/netbox/netbox.env.tpl"   -o "$REPO/netbox/netbox.env"   -f
            op inject -i "$REPO/netbox/postgres.env.tpl" -o "$REPO/netbox/postgres.env" -f
            op inject -i "$REPO/netbox/redis.env.tpl"    -o "$REPO/netbox/redis.env"    -f
            docker compose -f "$compose" up -d
            ;;
        *)
            if [ -f "$env_tpl" ]; then
                _op_run "$env_tpl" docker compose -f "$compose" up -d
            else
                docker compose -f "$compose" up -d
            fi
            ;;
    esac
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
