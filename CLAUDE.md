# CLAUDE.md

This file provides quick repository guidance for coding agents working in this repo.

## Current Architecture

The current supported path is the cloud-first GCP workflow described in [runbook.md](/D:/Internship/coin-ops-local/coin-ops/runbook.md) and [CONTEXT.md](/D:/Internship/coin-ops-local/coin-ops/CONTEXT.md).

Current runtime topology:

- `jump-host` — bastion only
- `nat-1` — dedicated NAT / egress VM for the private subnet
- `app-1` — public UI node with nginx gateway
- `app-2` — private backend node (proxy, history API, consumer, Redis/RabbitMQ when needed)

Traffic shape:

- browser -> Cloudflare -> `app-1` over HTTPS
- `app-1` -> `app-2` over internal TLS on `8443`
- `app-2` reaches the internet through `nat-1`

## Operator Workflow

Do **not** assume repo `.env` is the normal workflow.

Normal operator flow:

```bash
cd /mnt/d/Internship/coin-ops-local/coin-ops
source local/generated-env.sh

cd terraform
terraform plan
terraform apply

cd ..
ansible-playbook -i ansible/inventory ansible/provision.yml
ansible-playbook -i ansible/inventory ansible/deploy.yml
```

Bootstrap is handled by:

```bash
cd terraform
bash bootstrap-gcp.sh
```

Generated local files are gitignored and replace the older repo `.env` flow.

## Secrets

- Runtime secrets come from GCP Secret Manager during Ansible deploy.
- Do not hardcode credentials.
- Do not reintroduce `/etc/cognitor/*.env` as the primary application secret delivery path for current containerized services.

## Infrastructure Notes

- Terraform uses JSON-driven config in `terraform/config/`.
- Inventory truth is dynamic Ansible inventory, not `terraform/config/hosts.json`.
- SSH to private hosts goes through generated SSH config plus `ProxyJump` via `jump-host`.
- Stateful GCP resources are protected from casual destroy; intentional full teardown uses `terraform/full-destroy.sh`.

## Deployment Notes

- `app-1` and `app-2` may use the `coinops-app-host` golden image profile.
- Provisioning is image-aware and skips baked host-preparation work on golden-image app nodes.
- Internal backend TLS is enabled with `internal_tls_enabled=true`.
- Certbot renewal is timer-driven; use staging while repeatedly validating issuance behavior.

## Local Development

Local Compose convenience targets remain available from the repo root:

```bash
make local-up
make local-down
make local-logs
make local-ps
```

Service-specific commands:

```bash
cd ui-react && npm run dev
cd proxy && make run
cd history && python main.py
```

## Source of Truth

When this file conflicts with more detailed docs, prefer:

1. `runbook.md`
2. `CONTEXT.md`
3. `AGENTS.md`
