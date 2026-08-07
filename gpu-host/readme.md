# gpu-host exporters

> **This stack does not run on docker01.** It deploys to `gpu-host` — the RTX
> 3090 box, also reachable as `hermes`, at `192.168.1.43` / Tailscale
> `100.123.167.70`. It is deliberately **not** in `deploy.sh`'s stack list.

Prometheus and Grafana stay on docker01 and scrape across Tailscale. Only the
two exporters live here.

| | |
|---|---|
| `node-exporter` | `100.123.167.70:9100` — system metrics |
| `nvidia-gpu-exporter` | `100.123.167.70:9835` — GPU metrics |
| Scrape jobs | `monitoring/prometheus/prometheus.yaml` (`gpu-host-node`, `gpu-host-gpu`) |
| Dashboard | `monitoring/grafana/dashboards/gpu-host.json` → Grafana UID `gpu-host` |

## Deploy

Not managed by `deploy.sh` — that script runs on docker01 and would deploy this
to a machine with no GPU. Copy and bring it up on the target host:

```bash
ssh zbardwell@gpu-host 'mkdir -p ~/gpu-host-monitoring'
scp gpu-host/docker-compose.yaml zbardwell@gpu-host:~/gpu-host-monitoring/
ssh zbardwell@gpu-host 'cd ~/gpu-host-monitoring && docker compose up -d'
```

No secrets, so no `op run` — there is no `.env.tpl`.

## Why these choices

**Tailscale-only bind.** Both endpoints are unauthenticated: anything that can
reach them can read the host's full metric surface. Rather than exposing them
on `192.168.1.0/24`, both bind `100.123.167.70` explicitly. node-exporter uses
`--web.listen-address` (host netns means there is no port mapping to
restrict); the GPU exporter uses an IP-scoped `ports:` entry.

The cost is a boot-ordering dependency — if `tailscale0` has no address yet the
bind fails and the container exits. `restart: unless-stopped` retries until
Tailscale is up. Verified: LAN `192.168.1.43:9100` refuses, Tailscale answers.

**nvidia_gpu_exporter, not dcgm-exporter.** DCGM is NVIDIA's official option,
but its distinguishing feature is profiling counters (SM occupancy, DRAM
activity) that require a datacenter card. On a consumer 3090 it reports roughly
the same set as this exporter for a much larger image. Measured: 95 series
exposed, covering utilization, VRAM, temperature, power, clocks, and throttle
reasons.

**The `utility` GPU capability is required.** The reservation asks for
`capabilities: [gpu, utility]`. With `gpu` alone the NVIDIA toolkit does not
inject `nvidia-smi` into the container, and every scrape fails — this exporter
shells out to it.

**Targets are labelled `host`, not `device`.** The older `pikiosk` job uses
`device`, but `node_network_*` and `node_disk_*` already carry their own
`device` label. A colliding target label does not merge — Prometheus renames
the scraped one to `exported_device`, silently breaking per-interface and
per-disk queries. Dashboard panels select on `job` regardless.

## Dashboard notes

Temperature and fan speed are separate panels rather than one combined chart:
celsius and percent on a shared axis would be a dual-axis chart, which
misleads by making two unrelated scales look comparable.

VRAM, power, and load average each draw their ceiling (total / enforced limit /
core count) as a dashed reference line in the same unit as the series, so
"how close to the limit" is readable without a second axis.

`sw power cap` sitting at 1 under load is normal for a 3090 and is not a
problem; `hw thermal` or `hw power brake` going to 1 is.

Not added: alerting rules for GPU temperature or VRAM exhaustion. `monitoring/
prometheus/rules/` is where they would go if wanted.
