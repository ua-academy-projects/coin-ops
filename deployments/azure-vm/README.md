# CoinOps on Azure VM

This directory contains the Docker Compose runtime for the manually-created
Azure VM deployment.

## Runtime Flow

```text
Browser
  |
  v
Cloudflare DNS
  coinops-kazachuk.pp.ua -> 68.210.99.250
  |
  v
Azure Load Balancer :80/:443
  |
  v
Private Azure VM
  |
  v
Caddy :443
  |-- /             -> coinops-ui:80
  |-- /api          -> coinops-proxy:8080
  `-- /history-api  -> coinops-history-api:8000

coinops-proxy
  |-- RabbitMQ
  `-- Redis

coinops-history-consumer
  |-- RabbitMQ
  `-- PostgreSQL

coinops-history-api
  `-- PostgreSQL
```

## Files

| File | Purpose |
| --- | --- |
| `docker-compose.yml` | Runs the full CoinOps stack on one VM |
| `Caddyfile` | Public HTTPS entrypoint and path routing |
| `.env.example` | Safe example of required runtime variables |

## Why Caddy

Caddy is the reverse proxy for the VM deployment. It replaces the role that
Traefik Ingress had in Kubernetes:

- accepts public HTTP/HTTPS traffic;
- obtains and renews Let's Encrypt certificates;
- routes `/`, `/api`, and `/history-api` to the correct containers.

## Secrets

Do not commit a real `.env` file. The Ansible role renders `/opt/coinops/.env`
on the VM from the existing GCP Secret Manager values:

- `coinops-db-secrets`
- `coinops-service-secrets`

The VM does not need to know about GCP. Only the local Ansible run reads those
secrets and sends the final runtime config to the VM.

## Manual Checks On The VM

```bash
cd /opt/coinops
sudo docker compose ps
sudo docker compose logs -f caddy
sudo docker compose logs -f coinops-proxy
sudo docker compose logs -f coinops-history-api
sudo docker compose logs -f coinops-history-consumer
```

## External Checks

```bash
dig @1.1.1.1 coinops-kazachuk.pp.ua +short
curl -I https://coinops-kazachuk.pp.ua/
curl -I https://coinops-kazachuk.pp.ua/api/health
curl -I https://coinops-kazachuk.pp.ua/history-api/health
```
