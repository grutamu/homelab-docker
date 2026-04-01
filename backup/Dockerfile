FROM garethgeorge/backrest:latest
# Add postgresql client so pre-backup hooks can run pg_dump directly
# against DB containers over the internal Docker networks
RUN apk add --no-cache postgresql17-client
