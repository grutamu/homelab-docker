#!/bin/bash
# Create the read-only Grafana service account used by the `grafana` MCP server
# and store its token in 1Password.
#
#   ./scripts/grafana-service-account.sh
#
# Run from a workstation with the 1Password desktop integration: this needs to
# *write* to the vault, which Connect on docker01 cannot do. Reuses the service
# account if it already exists, so re-running only mints a fresh token — which
# is how you rotate. Old tokens stay valid until deleted in the Grafana UI.
#
# Prints character counts, never the token itself.
set -euo pipefail

GRAFANA=${GRAFANA_ADMIN_URL:-https://grafana.calzone.zone}
SA_NAME=mcp-grafana
SA_ROLE=Viewer

U=$(op read op://docker/monitoring/GF_SECURITY_ADMIN_USER)
P=$(op read op://docker/monitoring/GF_SECURITY_ADMIN_PASSWORD)

api() {
  local method=$1 path=$2 body=${3:-}
  if [ -n "$body" ]; then
    curl -sS -u "$U:$P" -X "$method" "$GRAFANA$path" \
      -H "Content-Type: application/json" --data-binary "$body"
  else
    curl -sS -u "$U:$P" -X "$method" "$GRAFANA$path"
  fi
}

EXISTING=$(api GET "/api/serviceaccounts/search?query=$SA_NAME" \
  | python3 -c "
import json,sys
d=json.load(sys.stdin)
for sa in d.get('serviceAccounts',[]):
    if sa.get('name')=='$SA_NAME':
        print(sa['id']); break
")

if [ -n "$EXISTING" ]; then
  SA_ID=$EXISTING
  echo "service account '$SA_NAME' already exists (id=$SA_ID), reusing"
else
  SA_ID=$(api POST /api/serviceaccounts \
    '{"name":"'"$SA_NAME"'","role":"'"$SA_ROLE"'","isDisabled":false}' \
    | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")
  echo "created service account '$SA_NAME' (id=$SA_ID, role=$SA_ROLE)"
fi

# Token names must be unique per service account, so count the existing ones.
N=$(api GET "/api/serviceaccounts/$SA_ID/tokens" \
  | python3 -c "import json,sys; print(len(json.load(sys.stdin)))")
TOKEN_NAME="mcpjungle-$((N + 1))"

TOKEN=$(api POST "/api/serviceaccounts/$SA_ID/tokens" \
  '{"name":"'"$TOKEN_NAME"'"}' \
  | python3 -c "import json,sys; print(json.load(sys.stdin)['key'])")

[ -n "$TOKEN" ] || { echo "token creation returned nothing" >&2; exit 1; }
echo "created token '$TOKEN_NAME' (${#TOKEN} chars)"

op item edit mcpjungle --vault docker \
  "GRAFANA_SERVICE_ACCOUNT_TOKEN[password]=$TOKEN" \
  "GRAFANA_URL[text]=http://grafana:3000" >/dev/null
echo "stored GRAFANA_SERVICE_ACCOUNT_TOKEN and GRAFANA_URL in 1Password"
echo
echo "Now re-register the server:  ./register-servers.py grafana"
