# llama.cpp Metrics on gpu-host

The **GPU Host** dashboard has a `llama.cpp` row fed by the inference server's
own Prometheus endpoint. Nothing in this repo turns that endpoint on — the
enabling change lives on gpu-host, in the separate `club-3090` estate repo.

## The endpoint

`llama-server` ships a built-in `/metrics` handler, but it is **disabled by
default** and answers every scrape with:

```
501  {"error":{"message":"This server does not support metrics endpoint. Start it with `--metrics`"}}
```

Prometheus treats a 501 as a failed scrape, so the row stays empty until the
flag is set. There is no exporter to install; this is not a sidecar.

## Enabling it (on gpu-host, not here)

gpu-host is a variant-switching estate, so **do not assume a path** — the live
compose file changes whenever `launch.sh` swaps models. Ask the running
container which file produced it:

```bash
ssh root@gpu-host 'docker inspect llama-cpp-qwen38-27b-single --format \
  "project={{index .Config.Labels \"com.docker.compose.project\"}}
config_files={{index .Config.Labels \"com.docker.compose.project.config_files\"}}
working_dir={{index .Config.Labels \"com.docker.compose.project.working_dir\"}}"'
```

As of 2026-08-21 that resolves to project `unsloth-iq4xs` and:

```
/home/zbardwell/club-3090/models/qwen3.8-27b/llama-cpp/compose/single/unsloth-iq4xs/q4kv-vision.yml
```

Add one line to that file's existing `environment:` block:

```yaml
    environment:
      - LLAMA_ARG_ENDPOINT_METRICS=1
      # ... existing SPEC_N / SPEC / LLAMA_ARG_CHAT_TEMPLATE_KWARGS / CUDA_VISIBLE_DEVICES
```

Then recreate from the reported `working_dir`, so the compose project name
resolves to the same value and the existing container is adopted rather than
orphaned. Reload is ~17s — the weights are already in page cache, so this is
not a cold 27B load.

The container currently runs entirely on compose defaults: no `ESTATE_*`
overrides are injected, `SPEC_N` and `SPEC` are both empty, and the only mount
is `/home/zbardwell/club-3090/models-cache -> /models (ro)`. A plain compose
recreate therefore reproduces the existing argv byte-for-byte — worth diffing
`docker inspect --format '{{json .Config.Cmd}}'` before and after, since adding
an env var must not perturb the command line.

**Use the env var, not the `--metrics` flag.** That compose file's `command:`
is a folded (`>-`) scalar and its header explicitly warns that comments cannot
live inside it; the env var is equivalent, applies regardless of how the
entrypoint wrapper rewrites argv for the drafter toggle, and leaves the
carefully-annotated command block untouched.

Only two of the estate's 134 compose files declare an `environment:` block, so
enabling this for a different variant may mean adding the block, not just the
line. Docker Compose forwards **only** what is declared there — putting
`LLAMA_ARG_ENDPOINT_METRICS=1` in the estate's top-level `.env` does nothing on
its own.

Verify:

```bash
ssh root@gpu-host 'curl -s http://localhost:8090/metrics | head'
```

## What you get

All ten metrics carry the `llamacpp:` prefix and no labels of their own beyond
what Prometheus attaches (`job="gpu-host-llama"`, `instance`, `host`).

| Metric | Type | Notes |
|---|---|---|
| `prompt_tokens_total` | counter | Prompt tokens ingested |
| `prompt_seconds_total` | counter | Seconds spent ingesting them |
| `tokens_predicted_total` | counter | Tokens generated |
| `tokens_predicted_seconds_total` | counter | Seconds spent generating them |
| `n_decode_total` | counter | `llama_decode()` calls |
| `n_busy_slots_per_decode` | counter | ⚠️ Mislabelled — holds an **average**, not a monotonic count. Do not `rate()` it. Useless at `-np 1` anyway |
| `prompt_tokens_seconds` | gauge | Last-request snapshot, spiky and stale between requests |
| `predicted_tokens_seconds` | gauge | Same caveat |
| `requests_processing` | gauge | 0 or 1 at `-np 1` |
| `requests_deferred` | gauge | Queued behind the single slot |

The dashboard prefers counter ratios over the two rate gauges, because the
gauges hold whatever the most recent request measured and go stale the moment
it finishes. `rate(tokens_predicted_total) / rate(tokens_predicted_seconds_total)`
is the same quantity averaged properly over the window, and it matches the
`print_timing` lines in the container log.

### Not exposed

- **KV cache usage.** `llamacpp:kv_cache_usage_ratio` and
  `kv_cache_tokens` appear in most llama.cpp monitoring writeups but were
  **removed upstream** and do not exist in `b10236`. Verified by extracting the
  metric-name strings from `libllama-server-impl.so` in the pinned image. This
  matters on this rig — the q4_0-KV-at-262K variant runs ~2.2 GiB of headroom,
  and that headroom is not observable here. Use `nvidia_smi_memory_used_bytes`
  from the GPU row instead.
- **Draft/MTP acceptance rate.** The server writes `draft acceptance = 0.845
  (186 accepted / 220 generated), mean len = 2.69` to its log and to no metric.
  The dashboard's **Speculative Gain** panel reconstructs it as
  `rate(tokens_predicted_total) / rate(n_decode_total)` — tokens emitted per
  decode call, which tracks `mean len` closely. Ceiling is 3 at
  `--spec-draft-n-max 2`; 1.0 means the drafter is pure overhead. For the real
  number, ship gpu-host's container logs to Loki (see [logging.md](logging.md) —
  Alloy currently only collects from docker01, so gpu-host is not covered).

## Operational notes

- **The target flaps by design.** gpu-host runs a variant-switching estate
  (`launch.sh --variant …`); each variant is its own container, and the scrape
  target is down between switches. No alert rule is attached to
  `gpu-host-llama` for this reason. The **Server Availability** panel exists to
  make the gaps legible rather than alarming.
- **A gap that never recovers** means the newly-launched variant either bound a
  port other than 8090 (`ESTATE_PORT`/`PORT`) or was started without the env
  var above — the estate's other compose files do not carry it.
- **Bind scope differs from the exporters.** `node-exporter` (9100) and
  `nvidia-gpu-exporter` (9835) deliberately bind the Tailscale address only.
  The llama.cpp container publishes 8090 on `0.0.0.0` because the inference API
  is used from the LAN, so `/metrics` is LAN-readable too. Prometheus reaches it
  over Tailscale regardless, since docker01 and gpu-host are on different
  subnets. Accepted as-is: it exposes no more than the inference API already does.
