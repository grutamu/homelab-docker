## run the following command to inject secrets in the env file

eval $(op signin)
op run --env-file=.env -- docker compose up -d

## first time setup
touch ./config/acme.json
chmod 600 ./config/acme.json