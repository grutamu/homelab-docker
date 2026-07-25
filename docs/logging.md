# Centralized Logging

All logs flow into Loki (`monitoring` stack) and are queryable from Grafana
(**Explore → Loki**). Retention is 30 days.

## What is collected

| Source | Collector | Labels |
|--------|-----------|--------|
| Every Docker container on docker01 | Alloy via Docker API | `container`, `service`, `stack`, `host=docker01` |
| docker01 host (systemd journal) | Alloy `loki.source.journal` | `job=journal`, `unit`, `host=docker01` |
| Non-Docker hosts (syslog) | Alloy syslog listener on `192.168.99.41:1514` | `job=syslog`, `host`, `app` |
| Pi Kiosk (`pikiosk`, IoT VLAN) | rsyslog forwarder → same syslog listener | `job=syslog`, `host=pikiosk`, `app` |

Notes:
- Container streams only appear in Loki after the container emits its first
  log line post-deploy; quiet containers (e.g. portainer) are still covered.
- Loki rejects entries older than 7 days, so a freshly added source drops its
  historical backlog once — this is expected, not data loss going forward.

## Syslog intake

Alloy listens on docker01 (`192.168.99.41`), port `1514`:

| Protocol | Format | Intended senders |
|----------|--------|------------------|
| UDP 1514 | RFC3164 (BSD) | Appliances with default syslog (UDM, TrueNAS, rsyslog default) |
| TCP 1514 | RFC5424 | Senders that can be configured explicitly |

Hosts on other VLANs (e.g. Proxmox on `192.168.10.0/24`) need a UDM firewall
rule permitting UDP/TCP 1514 to `192.168.99.41` if inter-VLAN traffic is
restricted.

## Per-device setup

### Proxmox (`192.168.10.10`)

Debian 12 / PVE 8 uses journald only; rsyslog must be installed to forward:

```bash
apt install -y rsyslog
cat > /etc/rsyslog.d/90-loki.conf <<'EOF'
*.* @192.168.99.41:1514
EOF
systemctl restart rsyslog
```

(`@` = UDP/RFC3164. Use `@@` for TCP, which requires RFC5424 — add
`;RSYSLOG_SyslogProtocol23Format` template suffix in that case.)

### Pi Kiosk (`pikiosk`, `192.168.2.70` on the IoT VLAN)

DietPi keeps a persistent journal and had no syslog daemon at all. rsyslog is
installed purely as a **forwarder** — the `& stop` suppresses Debian's default
local file rules, because journald already holds the persistent local copy and
duplicating it into `/var/log` only costs SD wear. Footprint is ~3.7 MB RSS,
which matters on a 512 MB box already budgeted around a 250 MB browser
watchdog.

```bash
apt install -y rsyslog
cat > /etc/rsyslog.d/90-loki.conf <<'EOF'
global(localHostname="pikiosk")
*.* @192.168.99.41:1514
& stop
EOF

# journald only writes to /dev/log when this is on; systemd defaults it off,
# so without this rsyslog forwards nothing.
mkdir -p /etc/systemd/journald.conf.d
printf '[Journal]\nForwardToSyslog=yes\n' \
  > /etc/systemd/journald.conf.d/10-forward-to-syslog.conf

systemctl restart systemd-journald rsyslog
```

Two things worth knowing:

- The hostname is overridden to `pikiosk` so the Loki `host` label matches the
  Prometheus `device="pikiosk"` label. The box's actual hostname is `DietPi`.
- rsyslog logs `STOP is followed by unreachable statements` on every start.
  That warning is the `& stop` working as intended — the distro's local file
  rules are deliberately unreachable.
- No UDM firewall rule was needed: the IoT VLAN already reaches
  `192.168.99.41:1514` (verified on both TCP and UDP).

**Blind spot:** logs ship over the network, so a wifi wedge — the exact fault
the kiosk suffers from — stops shipping. Loki captures the run-up, not the
moment of death; for that, use the persistent journal and
`/var/lib/systemd/pstore` on the Pi itself.

### TrueNAS SCALE (`192.168.99.10`)

UI: **System Settings → Advanced → Syslog** →
Syslog Server: `192.168.99.41:1514`, Transport: `UDP`. Save.

### UniFi UDM Pro

UI: **Settings → System → Advanced → Remote Logging** (location varies by
UniFi Network version; sometimes under **SIEM Server**) →
enable syslog, host `192.168.99.41`, port `1514`.

### AdGuard Home host (`192.168.99.5`)

AdGuard Home logs to its host's syslog/journal. If the host is Debian/Ubuntu,
use the same rsyslog snippet as Proxmox.

### Home Assistant (`192.168.99.204`) — optional

HAOS has no native syslog forwarding. Options: the community `syslog` add-on,
or leave HA logs local (it retains its own).

## Verifying a new sender

```bash
# from any host that should be forwarding:
logger -n 192.168.99.41 -P 1514 -d --rfc3164 "hello-loki"
```

Then in Grafana Explore: `{job="syslog"} |= "hello-loki"` — or check label
values: `{job="syslog"}` should show the sender under the `host` label.
