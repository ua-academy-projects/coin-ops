# GCP Deployment

This deployment uses the existing GCP infrastructure from the external
`gcp-terraform-bootstrap` project. Terraform owns the cloud layer, while this
repository owns the application deployment layer.

## Responsibility Split

`gcp-terraform-bootstrap` creates and manages:

- GCP VPC, subnet, firewall rules, and Cloud NAT
- GCP VM instances
- public jump/UI VM access
- Terraform state and backend configuration

`coin-ops` manages:

- Ansible inventory and host configuration
- Docker and Docker Compose installation
- per-node Compose stacks
- application containers and runtime environment files

Do not use `coin-ops/terraform` as the source of truth for this GCP deployment.
It belongs to the older VM lab flow.

## Current GCP Node Mapping

| App role | GCP VM | Address | Services |
| --- | --- | --- | --- |
| history | `vm-1` | `10.0.0.5` | PostgreSQL, RabbitMQ, history API, history consumer |
| proxy | `vm-2` | `10.0.0.2` | Go proxy, Redis |
| ui | `vm-4-jump` | `34.134.179.161` | nginx gateway, React UI |

`vm-1` and `vm-2` are private. Ansible reaches them through `vm-4-jump` using
SSH `ProxyJump`.

## Environment

Create a local `.env` file from the GCP example:

```bash
cp .env.gcp.example .env
```

Fill in real values:

- `RABBITMQ_PASSWORD`
- `DB_PASSWORD`
- `GHCR_USERNAME`
- `GHCR_TOKEN`

Load the environment before running Ansible:

```bash
source .env
```

## Provision VMs

Provision installs base packages, UFW, Docker, and Docker Compose on the target
VMs.

```bash
ansible-playbook -i ansible/inventory.gcp ansible/provision.yml
```

## Deploy Application

Deploy pulls GHCR images and starts per-node Docker Compose stacks.

```bash
ansible-playbook -i ansible/inventory.gcp ansible/deploy.yml
```

## Verify

```bash
curl http://34.134.179.161/health
curl http://34.134.179.161/api/health
curl http://34.134.179.161/history-api/health
```

Expected responses:

```json
{"status":"ok"}
```

```json
{"runtime_backend":"external","status":"ok"}
```

## HTTPS And Domain Plan

The first GCP deployment runs with:

```bash
export TLS_MODE="off"
export APP_DOMAIN="34.134.179.161"
```

For the final public setup:

1. Register the domain.
2. Move DNS management to Cloudflare.
3. Point an `A` record to `34.134.179.161`.
4. Set `APP_DOMAIN` to the real hostname.
5. Enable TLS with Cloudflare plus an origin certificate or move the public
   entrypoint to a GCP HTTPS Load Balancer with a managed certificate.

The direct-VM HTTP setup is useful for proving that the application works before
adding DNS, TLS, and load balancing.
