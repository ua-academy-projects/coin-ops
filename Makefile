SHELL := /bin/bash

REPO_ROOT := $(CURDIR)
TF_DIR := $(REPO_ROOT)/terraform
ANSIBLE_DIR := $(REPO_ROOT)/ansible
INVENTORY := $(ANSIBLE_DIR)/inventory
ENV_FILE := $(REPO_ROOT)/local/generated-env.sh
COMPOSE := docker compose

HOST ?=
LIMIT ?=
TF_APPLY_ARGS ?=
TF_DESTROY_ARGS ?=

ENV_PREFIX = source "$(ENV_FILE)" &&
ANSIBLE_CMD = $(ENV_PREFIX) ANSIBLE_CONFIG="$(REPO_ROOT)/ansible.cfg"

.PHONY: help \
	local-up local-down local-logs local-ps local-restart local-config \
	tf-check-backend tf-plan tf-apply tf-destroy-compute tf-full-destroy \
	inventory-graph inventory-host ssh-host \
	provision deploy

help:
	@echo "Local development:"
	@echo "  make local-up                - Run local docker compose stack"
	@echo "  make local-down              - Stop local docker compose stack"
	@echo "  make local-logs              - Tail local docker compose logs"
	@echo "  make local-ps                - Show local docker compose services"
	@echo "  make local-restart           - Rebuild and restart local docker compose stack"
	@echo "  make local-config            - Render local docker compose config"
	@echo ""
	@echo "Terraform / infrastructure:"
	@echo "  make tf-check-backend        - Verify backend.active.tf matches clouds.control_plane"
	@echo "  make tf-plan                 - Source generated env and run terraform plan"
	@echo "  make tf-apply                - Source generated env and run terraform apply"
	@echo "  make tf-destroy-compute      - Destroy only compute/runtime artifacts"
	@echo "  make tf-full-destroy         - Run deliberate full destroy helper"
	@echo ""
	@echo "Inventory / SSH:"
	@echo "  make inventory-graph         - Show Ansible inventory graph"
	@echo "  make inventory-host HOST=app-1"
	@echo "                               - Show resolved vars for a specific host"
	@echo "  make ssh-host HOST=coinops-gcp-app-1"
	@echo "                               - SSH using generated terraform ssh_config"
	@echo ""
	@echo "Ansible:"
	@echo "  make provision               - Run ansible/provision.yml"
	@echo "  make deploy                  - Run ansible/deploy.yml"
	@echo ""
	@echo "Optional variables:"
	@echo "  LIMIT=role_app_backend       - Pass --limit to provision/deploy"
	@echo "  TF_APPLY_ARGS='-auto-approve'"
	@echo "  TF_DESTROY_ARGS='-auto-approve'"

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

tf-check-backend:
	cd "$(TF_DIR)" && bash check-backend.sh

tf-plan:
	$(ENV_PREFIX) cd "$(TF_DIR)" && bash check-backend.sh && terraform plan

tf-apply:
	$(ENV_PREFIX) cd "$(TF_DIR)" && bash check-backend.sh && terraform apply $(TF_APPLY_ARGS)

tf-destroy-compute:
	$(ENV_PREFIX) cd "$(TF_DIR)" && bash check-backend.sh && terraform destroy \
		-target=module.gcp_nat_route \
		-target=module.gcp_instances \
		-target=module.aws_instances \
		-target=module.aws_nat_route \
		-target=module.azure_instances \
		-target=module.azure_nat_route \
		-target=local_file.hosts \
		-target=local_file.ssh_config \
		-target=local_file.ansible_runtime \
		-target=null_resource.sync_ssh_config \
		$(TF_DESTROY_ARGS)

tf-full-destroy:
	$(ENV_PREFIX) cd "$(TF_DIR)" && bash check-backend.sh && bash full-destroy.sh --yes-really-destroy-stateful $(TF_DESTROY_ARGS)

inventory-graph:
	$(ANSIBLE_CMD) ansible-inventory -i "$(INVENTORY)" --graph

inventory-host:
	@if [ -z "$(HOST)" ]; then echo "HOST is required, for example: make inventory-host HOST=app-1"; exit 1; fi
	$(ANSIBLE_CMD) ansible-inventory -i "$(INVENTORY)" --host "$(HOST)"

ssh-host:
	@if [ -z "$(HOST)" ]; then echo "HOST is required, for example: make ssh-host HOST=coinops-gcp-app-1"; exit 1; fi
	$(ENV_PREFIX) ssh -F "$(TF_DIR)/config/ssh_config" "$(HOST)"

provision:
	$(ANSIBLE_CMD) ansible-playbook -i "$(INVENTORY)" "$(ANSIBLE_DIR)/provision.yml" $(if $(LIMIT),--limit "$(LIMIT)",)

deploy:
	$(ANSIBLE_CMD) ansible-playbook -i "$(INVENTORY)" "$(ANSIBLE_DIR)/deploy.yml" $(if $(LIMIT),--limit "$(LIMIT)",)
