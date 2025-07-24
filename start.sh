#!/bin/bash
eval $(op signin)

#frigate
rm ./frigate/config/config.yml
op inject -i ./frigate/config/config.yml.tpl -o config/config.yml
docker compose -f ./frigate/docker-compose.yml up -d

#traefik
op run --env-file=./traefik/.env -- docker compose -f ./traefik/docker-compose.yml up -d