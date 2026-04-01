# Immich — already in 1Password
IMMICH_DB_USER=op://docker/immich/DB_USERNAME
IMMICH_DB_PASSWORD=op://docker/immich/DB_PASSWORD

# NetBox — add POSTGRES_PASSWORD to 1Password at op://docker/netbox/
NETBOX_DB_PASSWORD=op://docker/netbox/POSTGRES_PASSWORD

# Paperless — add POSTGRES_PASSWORD to 1Password at op://docker/paperless/
PAPERLESS_DB_PASSWORD=op://docker/paperless/POSTGRES_PASSWORD

# Restic repository password — used to encrypt the backup repo
# Generate with: openssl rand -base64 32
# Add to 1Password at op://docker/backrest/RESTIC_PASSWORD
RESTIC_PASSWORD=op://docker/backrest/RESTIC_PASSWORD
