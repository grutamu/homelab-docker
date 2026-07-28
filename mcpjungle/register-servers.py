#!/usr/bin/env python3
"""Re-register MCPJungle upstream servers from servers/*.json.

Every ${VAR} placeholder in servers/*.json is resolved from .env.register.tpl,
which maps each name to an `op://` reference, so rotating a credential means
updating 1Password and re-running this — no editing of committed files.

Usage:
    ./register-servers.py                 # every server in servers/
    ./register-servers.py proxmox unifi   # only these (file basenames)
    ./register-servers.py --dry-run       # resolve and validate, change nothing

Registration is delete-then-create because MCPJungle has no update endpoint;
a missing server on delete (404) is treated as fine. Servers are processed
independently, so one bad credential doesn't block the rest — the exit code is
non-zero if any failed.

Secrets are never printed or written to disk. Note that POST /api/v0/servers
echoes the registered env back in its response body in plaintext, so this
reports only names, status codes and tool counts. Don't add response dumps.

Requires `op` and python3. On docker01, run under `bash -l` so the
OP_CONNECT_* vars from /etc/profile.d/1password.sh are loaded; Connect is
read-only, which is all this needs.
"""

import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
SERVERS_DIR = os.path.join(HERE, "servers")
ENV_TPL = os.path.join(HERE, ".env.register.tpl")

REGISTRY = os.environ.get("MCPJUNGLE_REGISTRY", "https://mcp.calzone.zone")
ADMIN_TOKEN_REF = "op://docker/mcpjungle/ADMIN_TOKEN"

PLACEHOLDER = re.compile(r"\$\{([A-Z0-9_]+)\}")


def die(msg):
    sys.exit(f"error: {msg}")


def op_read(ref):
    """Resolve a single op:// reference. Never logs the value."""
    try:
        out = subprocess.run(
            ["op", "read", ref],
            capture_output=True, text=True, check=True,
        )
    except FileNotFoundError:
        die("`op` not found. Install the 1Password CLI, or run this on docker01.")
    except subprocess.CalledProcessError as e:
        stderr = (e.stderr or "").strip().splitlines()
        hint = stderr[-1] if stderr else "unknown error"
        die(f"could not read {ref}: {hint}")
    return out.stdout.strip()


def load_refs():
    """Parse .env.register.tpl into {VAR: op://reference}."""
    if not os.path.exists(ENV_TPL):
        die(f"missing {ENV_TPL}")
    refs = {}
    with open(ENV_TPL) as fh:
        for line in fh:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if "=" not in line:
                continue
            name, ref = line.split("=", 1)
            refs[name.strip()] = ref.strip()
    return refs


def api(method, path, token, payload=None):
    """Call the MCPJungle REST API. Returns (status, parsed_body_or_None)."""
    url = f"{REGISTRY.rstrip('/')}{path}"
    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Authorization", f"Bearer {token}")
    if data:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=180) as resp:
            body = resp.read().decode()
            return resp.status, (json.loads(body) if body.strip() else None)
    except urllib.error.HTTPError as e:
        body = e.read().decode()
        try:
            return e.code, json.loads(body)
        except json.JSONDecodeError:
            return e.code, {"error": body[:200]}
    except urllib.error.URLError as e:
        die(f"cannot reach {REGISTRY}: {e.reason}")


def resolve(path, refs, cache):
    """Substitute ${VAR} in a server config. Returns the parsed config."""
    raw = open(path).read()
    needed = set(PLACEHOLDER.findall(raw))
    missing = sorted(n for n in needed if n not in refs)
    if missing:
        die(f"{os.path.basename(path)} uses {', '.join(missing)}, "
            f"absent from .env.register.tpl")

    for name in sorted(needed):
        if name not in cache:
            cache[name] = op_read(refs[name])
        if cache[name] == "REPLACE_ME":
            die(f"{name} is still the REPLACE_ME placeholder in 1Password")

    filled = PLACEHOLDER.sub(lambda m: cache[m.group(1)], raw)
    try:
        return json.loads(filled)
    except json.JSONDecodeError as e:
        # A secret containing a quote or backslash would land here.
        die(f"{os.path.basename(path)} is not valid JSON after substitution: {e}")


def main():
    flags = [a for a in sys.argv[1:] if a.startswith("-")]
    if {"-h", "--help"} & set(flags):
        print(__doc__)
        return 0
    unknown = sorted(set(flags) - {"--dry-run"})
    if unknown:
        die(f"unknown flag(s): {', '.join(unknown)} (try --help)")

    args = [a for a in sys.argv[1:] if not a.startswith("-")]
    dry_run = "--dry-run" in flags

    if not os.path.isdir(SERVERS_DIR):
        die(f"missing {SERVERS_DIR}")

    paths = sorted(
        os.path.join(SERVERS_DIR, f)
        for f in os.listdir(SERVERS_DIR)
        if f.endswith(".json")
    )
    if args:
        wanted = set(args)
        paths = [p for p in paths
                 if os.path.basename(p)[: -len(".json")] in wanted]
        found = {os.path.basename(p)[: -len(".json")] for p in paths}
        for name in sorted(wanted - found):
            die(f"no servers/{name}.json")
    if not paths:
        die("no server configs found")

    refs = load_refs()
    cache = {}

    configs = [(p, resolve(p, refs, cache)) for p in paths]

    if dry_run:
        for path, cfg in configs:
            print(f"  ok   {cfg['name']:<16} "
                  f"({cfg.get('transport')}, from {os.path.basename(path)})")
        print(f"\n{len(configs)} config(s) resolved. Nothing was changed.")
        return 0

    token = os.environ.get("MCPJUNGLE_ADMIN_TOKEN") or op_read(ADMIN_TOKEN_REF)

    failures = 0
    for _, cfg in configs:
        name = cfg["name"]

        status, body = api("DELETE", f"/api/v0/servers/{name}", token)
        if status not in (200, 202, 204, 404):
            err = (body or {}).get("error", f"http {status}")
            print(f"  FAIL {name:<16} deregister: {err}")
            failures += 1
            continue

        status, body = api("POST", "/api/v0/servers", token, cfg)
        if status not in (200, 201):
            err = (body or {}).get("error", f"http {status}")
            print(f"  FAIL {name:<16} register: {err}")
            failures += 1
            continue

        status, body = api("GET", f"/api/v0/tools?server={name}", token)
        tools = body if isinstance(body, list) else (body or {}).get("tools", [])
        count = len(tools) if isinstance(tools, list) else "?"
        print(f"  ok   {name:<16} registered, {count} tools")

    total = len(configs)
    print(f"\n{total - failures}/{total} registered against {REGISTRY}")
    if failures:
        print("Check upstream stderr with: "
              "ssh root@docker01 'docker logs mcpjungle | tail -40'")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
