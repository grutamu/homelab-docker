# Librarr. Create the `librarr` item in the `docker` vault with these fields.
#
# API_KEY and TORZNAB_API_KEY are librarr's own — generate each with:
#   openssl rand -hex 32
API_KEY=op://docker/librarr/API_KEY
TORZNAB_API_KEY=op://docker/librarr/TORZNAB_API_KEY

# Copies of keys that already exist in the apps themselves. Prowlarr's is in
# Settings > General; SABnzbd's is in Config > General. Rotating either one in
# the app means updating it here too — librarr reads only this copy.
PROWLARR_API_KEY=op://docker/librarr/PROWLARR_API_KEY
SABNZBD_API_KEY=op://docker/librarr/SABNZBD_API_KEY

# The pocket-id OIDC client for librarr. Create it at auth.calzone.zone under
# OIDC Clients, with callback URL:
#   https://bookrequests.calzone.zone/auth/oidc/callback
# Pocket-id shows the secret once, at creation.
OIDC_CLIENT_ID=op://docker/librarr/OIDC_CLIENT_ID
OIDC_CLIENT_SECRET=op://docker/librarr/OIDC_CLIENT_SECRET
