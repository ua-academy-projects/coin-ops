COMPOSE := docker compose

.PHONY: local-up local-down local-logs local-ps local-restart local-config

local-up:
	$(COMPOSE) up -d --build

local-down:
	$(COMPOSE) down

local-logs:
	$(COMPOSE) logs -f

local-ps:
	$(COMPOSE) ps

local-restart:
	$(COMPOSE) down
	$(COMPOSE) up -d --build

local-config:
	$(COMPOSE) config
