#!/bin/bash

#frigate
docker compose -f ./trafrigateefik/docker-compose.yml down

#traefik
docker compose -f ./traefik/docker-compose.yml down