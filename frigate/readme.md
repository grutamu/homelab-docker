run the following commands to inject secrets
```
docker compose down
rm config/config.yml
op inject -i config/config.yml.tpl -o config/config.yml
docker compose up -d
```

## HomeKit

Cameras reach Apple Home through `go2rtc-homekit`, a second go2rtc alongside
the one Frigate embeds. It exists as its own container because HomeKit pairing
is HAP over mDNS and needs the host network namespace, which Frigate itself
must not take -- host mode would put its unauthenticated API on :5000 on the
LAN, where Traefik's OIDC middleware is the only thing guarding it today.

Config is split across two files, because go2rtc rewrites the first one it is
given as pairings happen:

| file | in git | holds |
|------|--------|-------|
| `config/go2rtc-homekit.yaml` | yes | streams, api listener, disabled rtsp/webrtc |
| `/docker-data/go2rtc-homekit/pairings.yaml` | no | `homekit:` exports, accessory keys, paired controllers |

To pair, open the Home app -> Add Accessory -> *More options...*, pick the
camera, and enter its PIN from `pairings.yaml` (`19550224` unless changed).
The WebUI at `http://docker-01.calzone.zone:1984` shows the same codes as QR
and is where you export a camera that is not in `pairings.yaml` yet.

Adding a camera means adding it in **both** files under the same stream key.
HomeKit takes H.264 video and OPUS audio only, so go2rtc runs an ffmpeg audio
transcode for each viewer -- Protect sends AAC.