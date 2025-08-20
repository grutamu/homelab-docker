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