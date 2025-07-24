#!/bin/bash
eval $(op signin)

#traefik
op run --env-file=./traefik/.env -- docker compose -f ./traefik/docker-compose.yaml up -d

#frigate
op inject -i ./frigate/config/config.yml.tpl -o ./frigate/config/config.yml -f
docker compose -f ./frigate/docker-compose.yaml up -d
