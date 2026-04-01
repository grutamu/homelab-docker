STACKS := traefik monitoring mediaserver immich frigate paperless netbox pocket-id audiobookshelf mealie portainer 1password

DC = docker compose -f $(stack)/docker-compose.yaml

# Validate that stack= is set and valid
check-stack:
ifndef stack
	$(error stack is required. Usage: make <target> stack=<name>)
endif
ifeq ($(filter $(stack),$(STACKS)),)
	$(error Unknown stack "$(stack)". Valid stacks: $(STACKS))
endif

##@ Single-stack operations (require stack=<name>)

up: check-stack ## Start a stack: make up stack=immich
	$(DC) up -d

down: check-stack ## Stop a stack: make down stack=immich
	$(DC) down

restart: check-stack ## Restart a stack: make restart stack=immich
	$(DC) restart

logs: check-stack ## Tail logs for a stack: make logs stack=immich
	$(DC) logs -f

pull: check-stack ## Pull latest images for a stack: make pull stack=immich
	$(DC) pull

update: check-stack ## Pull and redeploy a stack: make update stack=immich
	$(DC) pull && $(DC) up -d

ps: check-stack ## Show container status for a stack: make ps stack=immich
	$(DC) ps

##@ Multi-stack operations

up-all: ## Start all stacks
	@for s in $(STACKS); do \
		echo "==> Starting $$s"; \
		docker compose -f $$s/docker-compose.yaml up -d; \
	done

down-all: ## Stop all stacks
	@for s in $(STACKS); do \
		echo "==> Stopping $$s"; \
		docker compose -f $$s/docker-compose.yaml down; \
	done

pull-all: ## Pull latest images for all stacks
	@for s in $(STACKS); do \
		echo "==> Pulling $$s"; \
		docker compose -f $$s/docker-compose.yaml pull; \
	done

##@ Help

help: ## Show this help
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make <target> [stack=<name>]\n"} /^[a-zA-Z_-]+:.*?##/ { printf "  %-12s %s\n", $$1, $$2 } /^##@/ { printf "\n%s\n", substr($$0, 5) }' $(MAKEFILE_LIST)

.PHONY: check-stack up down restart logs pull update ps up-all down-all pull-all help
.DEFAULT_GOAL := help
