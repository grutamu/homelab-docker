# Pinned deliberately. On :latest this image was rebuilt only when the stack
# happened to be rebuilt, so the container sat on 1.12.1 (2026-03-11) while
# upstream moved to 1.14.1 — "latest" bought drift, not freshness. Worse, each
# unplanned rebuild recreated the container, and before the BACKREST_CONFIG fix
# that silently discarded the backup config. Renovate now proposes bumps as
# reviewable PRs (see the dockerfile manager in renovate.json).
# Note the `v`. Upstream publishes v1.14.1, not 1.14.1 — the unprefixed tag
# 404s, and so did the 1.12.1 this line carried before Renovate bumped it. That
# went unnoticed for months because `compose up -d` only builds when the image
# is *absent*, so the stack kept redeploying the locally cached layer: main said
# 1.14.1 while the container answered `backrest version: 1.12.1`. The --build in
# deploy.sh is what finally tried to resolve the tag and failed.
FROM garethgeorge/backrest:v1.14.1
# Add postgresql and mariadb clients so pre-backup hooks can run pg_dump /
# mariadb-dump directly against DB containers over the internal Docker networks
RUN apk add --no-cache postgresql17-client mariadb-client
