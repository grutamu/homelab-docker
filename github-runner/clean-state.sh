#!/bin/bash
# Wipe any stale runner state before delegating to the upstream entrypoint.
# Upstream only removes .runner, but config.sh treats .credentials* as
# "already configured" and refuses to re-register if a previous deregister
# failed (e.g. runner died mid-job or GitHub rejected the removal token).
rm -f /actions-runner/.runner \
      /actions-runner/.credentials \
      /actions-runner/.credentials_rsaparams \
      /actions-runner/.runner_migrated
exec /entrypoint.sh "$@"
