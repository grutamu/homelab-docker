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
# Order matters:
#   1password  first. Every stack with a .env.tpl is deployed through `op run`,
#              which needs Connect answering on :7070. On a host that is already
#              running this is invisible -- Connect is up from last time. On a
#              cold boot, nothing else can deploy until it is live.
#   traefik    second. It owns the `proxy` network that sixteen other stacks
#              attach to as external, so it has to exist before they start.
#   backup     last. It attaches to other stacks' networks as external.
STACKS=(1password traefik infra monitoring pocket-id
        mediaserver immich paperless frigate netbox
        audiobookshelf mealie portainer grimmory
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

# The same class of problem as prometheus, one layer deeper. Frigate's config is
# a bind mount, so editing it changes no part of the container spec, `compose
# up -d` leaves the running container alone, and frigate reads the file once at
# startup with no reload endpoint or signal. A config-only change deploys green
# and does nothing.
#
# Until 2026-09-16 it was worse than inert. The config was bound as a single
# *file*, which docker resolves to an inode at container creation, and the
# `op inject -f` below replaces the file rather than rewriting it in place. The
# container went on reading the old, unlinked inode, so a config change could
# not take effect even across a restart — only a full recreate rebound it. The
# compose file now binds the directory, which fixes visibility; this is the
# other half, making a visible change actually take effect.
#
# Restart rather than reload because there is nothing to reload — there is no
# POST /-/reload. That also sidesteps the SIGHUP race described above: a restart
# stops and starts the container cleanly rather than signalling a process that
# may still be coming up.
#
# Conditional on the content actually changing, so a full `deploy.sh` with no
# arguments does not bounce frigate every run, and skipped when compose already
# recreated the container — the same StartedAt test reload_prometheus uses.
frigate_started_at() {
    docker inspect -f '{{if .State.Running}}{{.State.StartedAt}}{{end}}' \
        frigate 2>/dev/null || true
}

restart_frigate_if_config_changed() {
    local before_sum=$1 after_sum=$2 before_start=$3 after_start

    if [ "$before_sum" = "$after_sum" ]; then
        echo "    frigate config unchanged — no restart needed"
        return
    fi

    after_start=$(frigate_started_at)

    if [ -z "$after_start" ]; then
        echo "    frigate is not running — skipping restart"
        return
    fi

    if [ "$before_start" != "$after_start" ]; then
        echo "    frigate was recreated — new config already loaded"
        return
    fi

    echo "    frigate config changed — restarting to apply it"
    docker restart frigate >/dev/null
}

# Block until 1Password Connect is answering. Starting the container is not the
# same as it being ready, and every `op run`/`op inject` below depends on it --
# without this, a cold boot races and each subsequent stack fails one by one.
# On a host where Connect is already up this returns on the first attempt.
wait_for_connect() {
    # Strip any trailing slash: OP_CONNECT_HOST=http://host:7070/ would
    # otherwise produce //heartbeat, which Connect does not serve.
    local url="${OP_CONNECT_HOST:-http://localhost:7070}"
    url="${url%/}/heartbeat"
    local i
    for i in $(seq 1 30); do
        if curl -fsS -o /dev/null "$url" 2>/dev/null; then
            [ "$i" -gt 1 ] && echo "    Connect ready after ${i} attempts"
            return 0
        fi
        sleep 2
    done
    echo "1Password Connect never became ready at $url (waited 60s)" >&2
    return 1
}

# Create the shared ingress network if it is missing. Seventeen stacks attach
# to `proxy` with `external: true`, so something has to create it before the
# first one starts -- on a cold host that something was nothing, and the deploy
# died on stack one with "network proxy declared as external, but could not be
# found".
#
# This lives here rather than as a compose-managed network in traefik because
# compose will not adopt a network it did not create: the one on docker01 was
# made by hand in Dec 2024 and carries no compose labels, so declaring it in
# traefik/docker-compose.yaml fails with "network proxy was found but has
# incorrect label com.docker.compose.network set to """ until every attached
# stack is stopped and the network rebuilt. Idempotent create, no downtime.
ensure_proxy_network() {
    docker network inspect proxy >/dev/null 2>&1 && return 0
    echo "==> creating missing \`proxy\` network"
    docker network create proxy
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

    # Stacks that build their own image (paperless, backup, adguard-sync) need
    # --build. `compose up -d` on its own builds only when the image is *absent*
    # from the local daemon, so once it exists nothing ever rebuilds it: an edit
    # to the Dockerfile, or a Renovate bump to the FROM line inside it, would
    # merge, deploy green, and leave the previously built image running. That is
    # the same silent drift that kept traefik on 3.7.9 while main said 3.7.10,
    # except no image tag changes to make it visible.
    #
    # Rebuilds are layer-cached, so this costs a second or two when nothing
    # changed. It deliberately does not pass --pull: refreshing the base image
    # is Renovate's job via the pinned FROM tag, and pulling here would mean an
    # unrelated deploy could silently move paperless onto a new base.
    local build_flag=()
    if [ -f "$REPO/$stack/Dockerfile" ]; then
        build_flag=(--build)
    fi

    if [ "$stack" = "1password" ]; then
        # Deployed with no secrets available -- Connect reads its credentials
        # from the bind-mounted 1password-credentials.json, not from op. That
        # is what makes it a valid first stack on a cold host.
        docker compose -f "$compose" up -d "${build_flag[@]}"
        wait_for_connect
    elif [ "$stack" = "frigate" ]; then
        local cfg="$REPO/frigate/config/config.yml"
        local cfg_before="" cfg_after frigate_before
        if [ -f "$cfg" ]; then
            cfg_before=$(sha256sum "$cfg" | cut -d' ' -f1)
        fi
        op inject -i "$REPO/frigate/config/config.yml.tpl" -o "$cfg" -f
        cfg_after=$(sha256sum "$cfg" | cut -d' ' -f1)
        frigate_before=$(frigate_started_at)
        docker compose -f "$compose" up -d "${build_flag[@]}"
        restart_frigate_if_config_changed "$cfg_before" "$cfg_after" "$frigate_before"
    elif [ "$stack" = "mediaserver" ]; then
        # Stays inside $REPO. This script runs in the github-runner container
        # during a CI deploy, and /root/homelab-docker is the only host path
        # mounted into it — writing to /docker-data works over ssh but fails
        # under CI with "No such file or directory". The compose file binds
        # this directory (not the file) into recyclarr as /config/configs,
        # which is where the inode problem is actually solved; see the comment
        # there.
        #
        # No restart needed afterwards, unlike frigate: the container runs
        # supercronic and each scheduled run execs a fresh `recyclarr sync`
        # that re-reads the config, so a change is picked up on the next run.
        local rc_cfg="$REPO/mediaserver/recyclarr/recyclarr.yml"
        op inject -i "$REPO/mediaserver/recyclarr/recyclarr.yml.tpl" \
                  -o "$rc_cfg" -f
        # recyclarr runs as uid 1000; op inject writes 0600 root, so hand
        # the resolved config to the container user (still not world-readable)
        chown 1000:1000 "$rc_cfg"
        docker compose -f "$compose" up -d "${build_flag[@]}"
    elif [ -f "$env_tpl" ]; then
        op run --env-file="$env_tpl" -- docker compose -f "$compose" up -d "${build_flag[@]}"
    else
        docker compose -f "$compose" up -d "${build_flag[@]}"
    fi

    if [ "$stack" = "monitoring" ]; then
        reload_prometheus "$prom_before"
    fi
}

cd "$REPO"
git pull

# Before anything is deployed, so that a single-stack run (`./deploy.sh immich`,
# which is how CI deploys) works on a cold host too, not just the full loop.
ensure_proxy_network

if [ $# -eq 1 ]; then
    deploy "$1"
else
    for stack in "${STACKS[@]}"; do
        deploy "$stack"
    done
fi

echo ""
echo "Done."
