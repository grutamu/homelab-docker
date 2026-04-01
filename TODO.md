# TODO

## Docker Deployment Improvements

- [ ] **Pin image versions** — Replace `:latest` tags with specific versions (e.g. `radarr:5.14.0`). Keeps a known-good version in git for rollbacks. Watchtower will still handle updates.

- [ ] **Control Watchtower scope** — Run Watchtower with `--label-enable` so updates are opt-in. Add `com.centurylinklabs.watchtower.enable=true` to services you want updated, and keep databases/stateful services out.

- [ ] **Move Watchtower and cf-tunnel out of `mediaserver`** — Both are infrastructure. Move to the `traefik` stack or a dedicated `infra` stack.

- [x] **Add a task runner** — Add a `Justfile` or `Makefile` at the repo root to simplify `up`, `logs`, `pull-up` operations across stacks (e.g. `make up stack=immich`).

- [ ] **Remove redundant `TZ` env vars** — `/etc/localtime` is already bind-mounted on most services. Pick one approach and apply it consistently.

- [ ] **Add healthchecks to databases and use `condition: service_healthy`** — Postgres and Redis containers lack healthchecks, so `depends_on` doesn't actually wait for readiness. Add `pg_isready` / `redis-cli ping` healthchecks and update `depends_on` conditions.

- [ ] **Replace Traefik basic auth with Pocket-ID SSO** — Pocket-ID is already running. Use the Traefik forward-auth middleware with Pocket-ID instead of the hashed-password basic auth on the dashboard.
