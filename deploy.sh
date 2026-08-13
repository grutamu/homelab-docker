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
#   gpu-host       exporters for the RTX 3090 box, deployed by hand (see its readme)
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

# Empty unless prometheus exists and is running.
prometheus_started_at() {
    docker inspect -f '{{if .State.Running}}{{.State.StartedAt}}{{end}}' \
        prometheus 2>/dev/null || true
}

# Prometheus reads its config and rules from a bind mount, so editing them
# changes no part of the container spec: `compose up -d` finds an up-to-date
# container and leaves it running untouched, and nothing watches the files. A
# rule change therefore deploys "successfully" and then sits on disk inert until
# some unrelated restart picks it up — which is how a *fixed* alert keeps paging.
#
# Two things this deliberately does not do, both learned on 2026-08-13:
#
# Not SIGHUP. `compose up -d` returns once the container is started, not once
# prometheus is ready, so a signal sent right after can land before prometheus
# installs its handler — where SIGHUP takes its default disposition and kills
# the process. `docker kill` also marks the container manually-stopped, so
# `restart: unless-stopped` does not bring it back. That combination took
# prometheus down for ~2min. POST /-/reload cannot kill it, and it reports a
# config that fails to load instead of leaving prometheus silently serving the
# previous one.
#
# Not unconditional. If compose recreated the container (image bump, spec
# change) it already booted with the new config, and reloading a process that is
# still starting up is the race described above. A changed StartedAt is the
# signal that no reload is needed.
reload_prometheus() {
    local before=$1 after
    after=$(prometheus_started_at)

    if [ -z "$after" ]; then
        echo "    prometheus is not running — skipping reload"
        return
    fi

    if [ "$before" != "$after" ]; then
        echo "    prometheus was recreated — new config already loaded"
        return
    fi

    echo "    reloading prometheus"
    docker exec prometheus \
        wget -q -O- --post-data='' http://localhost:9090/-/reload >/dev/null
}

deploy() {
    local stack=$1
    local compose="$REPO/$stack/docker-compose.yaml"
    local env_tpl="$REPO/$stack/.env.tpl"

    [ -f "$compose" ] || { echo "No compose file for '$stack', skipping."; return; }

    echo "==> $stack"

    local prom_before=""
    if [ "$stack" = "monitoring" ]; then
        prom_before=$(prometheus_started_at)
    fi

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

    if [ "$stack" = "monitoring" ]; then
        reload_prometheus "$prom_before"
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
