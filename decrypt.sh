#!/bin/bash
eval $(op signin)

#traefik
op inject -i ./traefik/.env.tpl -o ./traefik/.env -f

#frigate
op inject -i ./frigate/config/config.yml.tpl -o ./frigate/config/config.yml -f

#mediaserver stack
op inject -i ./mediaserver/.env.tpl -o ./mediaserver/.env -f

#monitoring stack
op inject -i ./monitoring/.env.tpl -o ./monitoring/.env -f

#netbox stack
op inject -i ./netbox/netbox.env.tpl -o ./netbox/netbox.env -f
op inject -i ./netbox/postgres.env.tpl -o ./netbox/postgres.env -f
op inject -i ./netbox/redis.env.tpl -o ./netbox/redis.env -f

#immich
op inject -i ./immich/.env.tpl -o ./immich/.env -f

#paperless
op inject -i ./paperless/.env.tpl -o ./paperless/.env -f

#pocket-id
op inject -i ./pocket-id/.env.tpl -o ./pocket-id/.env -f