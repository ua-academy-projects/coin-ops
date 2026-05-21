COMPOSE := docker compose -f deployments/local/docker-compose.yml

.PHONY: local-up local-down local-logs local-ps local-restart local-config smoke smoke-postgres

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

smoke:
	./deployments/smoke/smoke.sh

smoke-postgres:
	./deployments/smoke/smoke.sh postgres-runtime
