run the following commands to inject secrets
```
docker compose down
rm config/config.yml
op inject -i config/config.yml.tpl -o config/config.yml
docker compose up -d
```