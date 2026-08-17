# Grimmory's own MariaDB. Create the `grimmory` item in the `docker` vault.
# Generate each with: openssl rand -base64 32
#
# DATABASE_PASSWORD and MARIADB_PASSWORD are the same secret under two names:
# one is what grimmory connects with, the other is what MariaDB provisions the
# `grimmory` user with on first boot. They must not drift.
DATABASE_PASSWORD=op://docker/grimmory/DATABASE_PASSWORD
MARIADB_PASSWORD=op://docker/grimmory/DATABASE_PASSWORD
MARIADB_ROOT_PASSWORD=op://docker/grimmory/MARIADB_ROOT_PASSWORD
