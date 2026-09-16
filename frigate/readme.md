# Frigate

NVR for the UniFi Protect cameras. Object detection runs on the Intel Arc A310
via OpenVINO; the cameras themselves are pulled from the UDM through go2rtc.

## Deploying

```bash
ssh root@docker01 'bash -l -c "/root/homelab-docker/deploy.sh frigate"'
```

`deploy.sh` resolves `config/config.yml.tpl` into `config/config.yml` with
`op inject`, then brings the stack up. It restarts the container when the
resolved config changed, because Frigate reads its config once at startup and
has no reload endpoint. Nothing else picks up a config edit — editing the file
by hand does nothing until something restarts the container.

`config/config.yml` is gitignored: it holds the resolved MQTT password. Never
commit it, and edit the `.tpl` instead — the resolved file is overwritten on
every deploy.

## Upgrading

The image tag and the `version:` at the bottom of the template **must move in
the same commit**.

Frigate migrates a config it considers older than the running release, and the
config models are `extra="forbid"`, so a schema change that isn't reflected in
the template is a hard startup failure. Keeping `version:` current means no
migration runs at all — which is the point, but it has a consequence:

> **Migrations supply defaults. A version-pinned config gets none of them, so
> anything a migration would have set has to be written down explicitly.**

That is not theoretical. `detect.enabled` defaults to `False` and was only ever
set by `migrate_016_0()`. Pinning `version:` to `0.18-0` turned object
detection off on every camera while recording carried on normally — silent,
because `motion.enabled` is independent and continuous recording never stopped.
Hence the explicit `detect: enabled: true`.

Before bumping, read the release notes for removed keys, then verify against
the real image rather than guessing:

```bash
# validate the resolved config against the new version
docker run --rm --entrypoint python3 \
  -e CONFIG_FILE=/config-src/config.yml \
  -v /root/homelab-docker/frigate/config:/config-src:ro \
  ghcr.io/blakeblackshear/frigate:<tag> -u -m frigate --validate-config
```

Renovate is set to `automerge: false` for this stack. A Frigate `0.x` bump is a
semver *minor*, so the global "never automerge major" rule does not catch it.

## Why the config is mounted as a directory

`compose` binds `./config` (the directory) to `/config-src`, and `CONFIG_FILE`
points Frigate at it. It is deliberately not a single-file bind of
`config.yml`.

Docker resolves a single-file bind to an inode once, at container creation.
`op inject -f` *replaces* the file rather than rewriting it in place, so the
container goes on reading the old, unlinked inode — and a restart does not
rebind it, only a full recreate does. Every config-only deploy went green and
changed nothing. A directory bind resolves each lookup at access time.

`/config` can't hold the config instead: that's the data dir bind
(`frigate.db`, `model_cache`, jwt secret).

## Detector

`device: GPU`, not `AUTO`. `AUTO` silently falls back to the CPU when the
OpenVINO GPU plugin can't initialise — detection keeps working, so the only
symptom is CPU load. Pinning it makes a broken Level Zero / compute-runtime
stack fail loudly, which matters when the host moves to NixOS.

The model is the SSDLite MobileNet v2 bundled in the image at
`/openvino-model/`. `labelmap_path` is set explicitly; without it the bundled
model's classes are offset by one and people get detected as "bicycle".

0.18 rebuilt this model's OpenVINO conversion specifically because the previous
one produced ops the GPU plugin handled badly, so the GPU pin benefits from it.

## Cameras

Every camera pulls two go2rtc streams, low-res for `detect` and high-res for
`record`, except `packagecam` which only exposes one and uses it for both.

| camera | detect | record |
|---|---|---|
| `frigate_front` | 640×360 | 2688×1512 |
| `frigate_frontdoor` | 480×360 | 1600×1200 |
| `frigate_patio` | 640×360 | 3840×2160 |
| `frigate_garage` | 640×360 | 2688×1512 |
| `frigate_packagecam` | 1600×1200 | 1600×1200 |

Stream URLs use `rtspx://`, which is go2rtc's UniFi Protect scheme. It is the
equivalent of the `rtsps://…?enableSrtp` URL that the Protect UI hands out —
drop the scheme's `s`, drop the query string. Both forms work, but keep the
whole file on `rtspx://` so they stay comparable.

`preset-record-ubiquiti` stream-copies video and re-encodes audio to 44.1 kHz
AAC, which is what makes Protect's recordings play back correctly.

Detection is limited to `person` and `car` (`objects.track`), and both raise
alerts (`review.alerts.labels`). Other labels the bundled model supports —
`dog`, `cat`, `bicycle`, `motorcycle`, `bus`, `bird` — can be added to either
list. `face`, `license_plate` and `package` are *not* tracked objects in 0.16+;
they are enrichments with their own config sections.

## Storage

Recordings go to TrueNAS over NFS (`/mnt/ssd-pool/frigate`), 3 days continuous
plus 30 days of motion-only for alerts and detections. `frigate_patio` records
at 4K, so it will consume noticeably more than the others.

`shm_size` is 450 MB. Frigate needs roughly
`(w × h × 1.5 × 9 + 270480)` bytes per camera for the *detect* resolution, so
the 1600×1200 packagecam dominates. Check `docker exec frigate df -h /dev/shm`
after adding a camera.
