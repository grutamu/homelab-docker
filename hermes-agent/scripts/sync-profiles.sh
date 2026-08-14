#!/bin/bash
# Apply the versioned sub-agent profiles in ../profiles/ to the live agent.
#
# Hermes' data dir (/docker-data/hermes-agent) is agent-mutable state: the agent
# edits its own skills, memories and sessions there, and none of it is in git.
# A profile's *identity* is the opposite — SOUL.md and the config that scopes its
# tools are authored, reviewed and diffed like any other file in this repo. This
# script is the one-way bridge: repo -> data dir. Nothing reads back.
#
# Usage:
#   ./sync-profiles.sh              # every profile in ../profiles/
#   ./sync-profiles.sh obs netops   # only these
#   DRY_RUN=1 ./sync-profiles.sh    # print what would change, touch nothing
#
# Safe to re-run: creating an existing profile is skipped, and `hermes config
# set` is idempotent. Run it after every change to a SOUL.md or profile.conf.
#
# Slow by construction — every directive is a separate `hermes` invocation, and
# each one is a Python process that loads the whole CLI. A full sync of three
# profiles is ~100 spawns and takes minutes. That is the cost of using the
# supported write path instead of editing config.yaml; don't "optimise" it by
# generating YAML directly.

set -euo pipefail

CONTAINER=hermes-agent
REPO_PROFILES=$(cd "$(dirname "$0")/../profiles" && pwd)
DATA_PROFILES=/docker-data/hermes-agent/profiles

# Matches HERMES_UID / HERMES_GID in docker-compose.yaml — the s6 stage2 hook
# remaps the container's `hermes` user to these. A SOUL.md owned by root is a
# file the agent cannot read.
HERMES_UID=1000
HERMES_GID=1000

DRY_RUN=${DRY_RUN:-}

docker ps --format '{{.Names}}' | grep -qx "$CONTAINER" || {
    echo "$CONTAINER is not running. Start it first — every step here runs" >&2
    echo "through 'docker exec' and 'hermes config set'." >&2
    exit 1
}

# `hermes config set` rather than templating config.yaml: upstream's stated
# invariant is never to hand-edit that file, and a stray indent takes the live
# gateway down with it. Slower, but it is the supported write path.
hermes_run() {
    if [ -n "$DRY_RUN" ]; then
        echo "      would run: hermes $*"
        return 0
    fi
    docker exec "$CONTAINER" hermes "$@" </dev/null
}

sync_profile() {
    local name=$1
    local dir=$REPO_PROFILES/$name
    local soul=$dir/SOUL.md
    local conf=$dir/profile.conf

    [ -d "$dir" ] || { echo "  ✗ no such profile in repo: $name" >&2; return 1; }
    echo "── $name"

    # `describe` is not decoration. The kanban decomposer routes triage tasks by
    # reading every profile's description, so this text is what decides whether
    # a card lands here or somewhere else. It is separate from SOUL.md on
    # purpose: SOUL.md is how the agent behaves, this is how the board finds it.
    local description=''
    [ -f "$conf" ] && description=$(sed -n 's/^describe  *//p' "$conf" | head -1)

    if docker exec "$CONTAINER" hermes profile list 2>/dev/null | grep -qE "[◆ ]$name +"; then
        echo "  · profile exists"
    else
        echo "  + creating profile"
        # --clone-from default, and not a bare create, for one specific reason:
        # `model.provider: custom:…` requires a matching entry in the
        # `custom_providers` LIST, and there is no supported way to write a YAML
        # list into config.yaml. `hermes config set custom_providers.0.name …`
        # produces a dict keyed '0' (doctor: "custom_providers is a dict — it
        # must be a YAML list"), and `config set --force` stores the JSON as a
        # literal string. Cloning inherits the list already-valid. There is no
        # generic `openai` provider to fall back on — that name is rejected too.
        #
        # --no-alias: wrapper scripts in the data dir are for humans at a shell,
        # and nobody gets an interactive shell in this container.
        hermes_run profile create "$name" --clone-from default --no-alias \
            ${description:+--description "$description"}

        # The clone also copies default's .env. It holds no credentials (16
        # entries, all TERMINAL_*/BROWSER_*/*_DEBUG tuning plus default's own
        # DISCORD_* ids — the stack readme is accurate on this), but none of it
        # applies to a specialist: terminal and browser are disabled in these
        # profiles, and the Discord ids belong to default's gateway. A per-profile
        # copy would only drift. Everything a specialist actually needs — the
        # MCP_*_API_KEYs — comes from the container environment via op run.
        if [ -z "$DRY_RUN" ]; then
            rm -f "$DATA_PROFILES/$name/.env"
            echo "  · dropped cloned .env (default's tuning, not applicable here)"
        else
            echo "      would drop cloned .env"
        fi
    fi
    # --text, not a positional: an unflagged description is parsed as extra
    # arguments and the command fails. --text also overwrites, which is what we
    # want — the repo is the source of truth, not whatever `--auto` guessed.
    [ -n "$description" ] && hermes_run profile describe "$name" --text "$description" >/dev/null

    if [ -f "$soul" ]; then
        local bytes
        bytes=$(wc -c <"$soul" | tr -d ' ')
        # SOUL.md is injected into every prompt this profile ever builds, and the
        # live default profile already sits around 65k tokens against a single
        # 128k llama.cpp slot. A soul that sprawls costs latency on every turn.
        if [ "$bytes" -gt 3072 ]; then
            echo "  ! SOUL.md is ${bytes}B (>3072B budget) — trim it"
        fi
        if [ -n "$DRY_RUN" ]; then
            echo "      would install SOUL.md (${bytes}B)"
        else
            install -o "$HERMES_UID" -g "$HERMES_GID" -m 644 \
                "$soul" "$DATA_PROFILES/$name/SOUL.md"
            echo "  ✓ SOUL.md installed (${bytes}B)"
        fi
    else
        echo "  ! no SOUL.md — this profile has no identity of its own"
    fi

    [ -f "$conf" ] || return 0

    # Directives, one per line. Only the first one or two fields are split, so
    # values may contain spaces (model paths, provider names, descriptions).
    local directive rest key value
    while read -r directive rest; do
        case "$directive" in
            ''|'#'*|describe) continue ;;
            set)
                key=${rest%% *}
                value=${rest#* }
                hermes_run -p "$name" config set "$key" "$value" >/dev/null
                echo "  · set $key"
                ;;
            enable|disable)
                # A toolset absent from a profile's build is not just disallowed,
                # it is absent from the schema — the model never sees it and
                # cannot narrate its way around it.
                if hermes_run -p "$name" tools "$directive" "$rest" >/dev/null 2>&1; then
                    echo "  · $directive $rest"
                else
                    echo "  ! tools $directive $rest failed (unknown toolset?)"
                fi
                ;;
            *)
                echo "  ! unknown directive in profile.conf: $directive" >&2
                ;;
        esac
    done <"$conf"
    echo "  ✓ config applied"
}

targets=("$@")
if [ ${#targets[@]} -eq 0 ]; then
    targets=()
    for d in "$REPO_PROFILES"/*/; do targets+=("$(basename "$d")"); done
fi

[ -n "$DRY_RUN" ] && echo "DRY RUN — nothing will be written"
for t in "${targets[@]}"; do sync_profile "$t"; done

echo
echo "Toolset changes take effect on a new session, never mid-conversation —"
echo "that is deliberate upstream, to avoid invalidating the prompt cache."
