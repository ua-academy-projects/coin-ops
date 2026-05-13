# GCP Deployment

This deployment uses the external `gcp-terraform-bootstrap` project for the
cloud layer. This repository owns only application provisioning and deployment.

## Responsibility Split

`gcp-terraform-bootstrap` creates and manages:

- GCP VPC, subnet, firewall rules, Cloud NAT, and Private Services Access
- private GCP VM instances plus a public jump host
- GCP HTTPS Load Balancer and Google-managed SSL certificate
- Cloud SQL for PostgreSQL with private IP only
- GCP Secret Manager secret containers
- Terraform state and backend configuration

`coin-ops` manages:

- Ansible inventory and host configuration
- Docker and Docker Compose installation
- per-node Compose stacks
- application containers
- runtime secret loading from GCP Secret Manager

Do not use `coin-ops/terraform` as the source of truth for this GCP deployment.
It belongs to the older VM lab flow.

## Current GCP Node Mapping

| App role | GCP VM | Address | Services |
| --- | --- | --- | --- |
| history | `vm-1` | `10.0.0.5` | RabbitMQ, history API, history consumer |
| proxy | `vm-2` | `10.0.0.2` | Go proxy, Redis |
| ui | `vm-3` | `10.0.0.4` | nginx gateway, React UI |
| bastion | `vm-4-jump` | public + `10.0.0.3` | SSH jump host only |

`vm-1`, `vm-2`, and `vm-3` are private. Ansible reaches them through
`vm-4-jump` using SSH `ProxyJump`.

PostgreSQL is not deployed as a container in the GCP runtime anymore. The
application uses Cloud SQL PostgreSQL over a private IP inside the VPC.

## Secrets

Sensitive values are stored in GCP Secret Manager, grouped by purpose:

- `coinops-db-secrets` contains database secrets.
- `coinops-service-secrets` contains RabbitMQ and registry secrets.

Expected JSON shape:

```json
{
  "db_user": "cognitor",
  "db_password": "replace-me",
  "db_name": "cognitor"
}
```

```json
{
  "rabbitmq_user": "cognitor",
  "rabbitmq_password": "replace-me",
  "ghcr_username": "replace-me",
  "ghcr_token": "replace-me"
}
```

Ansible reads these secrets directly during `ansible/deploy.yml`. It does not
write `/etc/cognitor/*.env` files and does not require `source .env`.

## Provision VMs

Provision installs base packages, UFW, Docker, and Docker Compose on the target
VMs.

```bash
ansible-playbook -i ansible/inventory.gcp ansible/provision.yml
```

## Deploy Application

Deploy pulls GHCR images, ensures the Cloud SQL application user exists, applies
the history schema to Cloud SQL, and starts per-node Docker Compose stacks.

```bash
ansible-playbook -i ansible/inventory.gcp ansible/deploy.yml
```

## Verify

```bash
curl -i https://coinops-kazachuk.pp.ua
curl -i https://coinops-kazachuk.pp.ua/api/health
curl -i https://coinops-kazachuk.pp.ua/history-api/health
```

Expected health responses:

```json
{"runtime_backend":"external","status":"ok"}
```

```json
{"status":"ok"}
```

## Public HTTPS Path

The final public setup is:

```text
Cloudflare DNS -> GCP HTTPS Load Balancer -> private vm-3 UI -> vm-2 proxy -> vm-1 history-api -> Cloud SQL PostgreSQL
```

TLS terminates at the GCP HTTPS Load Balancer with a Google-managed
certificate. The UI container remains HTTP-only on the private backend VM.
