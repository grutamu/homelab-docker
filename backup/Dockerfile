# Pinned deliberately. On :latest this image was rebuilt only when the stack
# happened to be rebuilt, so the container sat on 1.12.1 (2026-03-11) while
# upstream moved to 1.14.1 — "latest" bought drift, not freshness. Worse, each
# unplanned rebuild recreated the container, and before the BACKREST_CONFIG fix
# that silently discarded the backup config. Renovate now proposes bumps as
# reviewable PRs (see the dockerfile manager in renovate.json).
FROM garethgeorge/backrest:1.14.1
# Add postgresql and mariadb clients so pre-backup hooks can run pg_dump /
# mariadb-dump directly against DB containers over the internal Docker networks
RUN apk add --no-cache postgresql17-client mariadb-client
