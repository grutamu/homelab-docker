import re
import os
import logging
import requests
import docker

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger(__name__)

ADGUARD_URL   = os.environ["ADGUARD_URL"].rstrip("/")
ADGUARD_USER  = os.environ["ADGUARD_USER"]
ADGUARD_PASS  = os.environ["ADGUARD_PASSWORD"]
CNAME_TARGET  = os.environ.get("CNAME_TARGET", "docker-01.calzone.zone")

HOST_RE = re.compile(r'Host\(`([^`]+)`\)')


def session():
    s = requests.Session()
    s.auth = (ADGUARD_USER, ADGUARD_PASS)
    return s


def list_rewrites(s):
    r = s.get(f"{ADGUARD_URL}/control/rewrite/list")
    r.raise_for_status()
    return {e["domain"]: e["answer"] for e in r.json()}


def add_rewrite(s, domain):
    existing = list_rewrites(s)
    if domain in existing:
        log.debug(f"Rewrite already exists: {domain}")
        return
    s.post(f"{ADGUARD_URL}/control/rewrite/add",
           json={"domain": domain, "answer": CNAME_TARGET}).raise_for_status()
    log.info(f"Added:   {domain} → {CNAME_TARGET}")


def remove_rewrite(s, domain):
    existing = list_rewrites(s)
    if domain not in existing:
        return
    s.post(f"{ADGUARD_URL}/control/rewrite/delete",
           json={"domain": domain, "answer": existing[domain]}).raise_for_status()
    log.info(f"Removed: {domain}")


def hosts_from_labels(labels):
    return [
        host
        for key, value in labels.items()
        if re.match(r"traefik\.http\.routers\..+\.rule", key)
        for host in HOST_RE.findall(value)
    ]


def main():
    client = docker.from_env()
    s = session()

    log.info("Initial sync of running containers...")
    for container in client.containers.list():
        for host in hosts_from_labels(container.labels):
            try:
                add_rewrite(s, host)
            except Exception as e:
                log.error(f"Failed to add {host}: {e}")

    log.info("Watching Docker events (start / destroy)...")
    for event in client.events(decode=True, filters={"type": "container", "event": ["start", "destroy"]}):
        action = event["Action"]
        attrs  = event["Actor"]["Attributes"]
        hosts  = hosts_from_labels(attrs)

        for host in hosts:
            try:
                if action == "start":
                    add_rewrite(s, host)
                elif action == "destroy":
                    remove_rewrite(s, host)
            except Exception as e:
                log.error(f"Failed to handle {action} for {host}: {e}")


if __name__ == "__main__":
    main()
