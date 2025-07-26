#!/bin/bash
eval $(op signin)

#traefik
op inject -i ./traefik/.env.tpl -o ./traefik/.env -f

#frigate
op inject -i ./frigate/config/config.yml.tpl -o ./frigate/config/config.yml -f
