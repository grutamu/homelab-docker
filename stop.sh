#!/bin/bash

#frigate
docker compose -f ./frigate/docker-compose.yaml down

#traefik
docker compose -f ./traefik/docker-compose.yaml down