# CoinOps Runbook

This runbook describes the hybrid infrastructure: **Docker Compose** for applications and a **Vagrant VM** for the PostgreSQL database.

## Infrastructure Overview

| Component | Type | Host/Network | Port (Local Access) |
| --- | --- | --- | --- |
| **Frontend** | Docker | localhost | `5000` |
| **Proxy** | Docker | localhost | `8081` |
| **History Service** | Docker | localhost | `8090` |
| **RabbitMQ** | Docker | internal | — |
| **Redis** | Docker | internal | — |
| **PostgreSQL** | Vagrant VM | `10.10.1.6` | `5432` |

## Deployment & Operational Flow

### 1. Preparation
Configuration is managed centrally via Ansible Vault.
- **Secrets**: Ensure `infra/group_vars/all/vault.yml` is populated.
- **Auto-generation**: The `.env` file for Docker will be automatically generated in the `infra/` folder during the `vagrant up` or `vagrant provision` process.
- **Note**: You do not need to edit `.env` manually anymore.

### 2. Start Infrastructure (VM)
One virtual machine is required for the database.
```bash
cd infra
vagrant up
```
*Note: Vagrant will use Ansible to provision the PostgreSQL instance on IP `10.10.1.6`.*

### 3. Start Applications (Docker)
Run the application stack using Docker Compose from the `infra/` folder.
```bash
cd infra
docker compose up -d
```

## Internal Network Communication (DNS)

Inside the Docker network, services communicate using their container names as DNS hosts:

| From | To | Protocol | Hostname | Port |
| --- | --- | --- | --- | --- |
| Frontend | Proxy | HTTP | `proxy` | `8080` |
| Frontend | History Service | HTTP | `history_service` | `8090` |
| Frontend | Redis | TCP | `redis` | `6379` |
| Proxy | RabbitMQ | AMQP | `rabbitmq` | `5672` |
| History Service | RabbitMQ | AMQP | `rabbitmq` | `5672` |
| History Service | PostgreSQL | TCP | `10.10.1.6` | `5432` |

## Smoke Tests

1. **Frontend UI**: Open [http://localhost:5000](http://localhost:5000) in your browser.
2. **Live Rates (Proxy)**:
   ```bash
   curl -sS http://localhost:8081/api/v1/rates | jq '.rates | length'
   ```
3. **History API**:
   ```bash
   curl -sS "http://localhost:8090/api/v1/history?limit=5" | jq '.count'
   ```
4. **Database Check** (inside VM):
   ```bash
   ssh -p 2205 vagrant@localhost  # or vagrant ssh database
   psql -h 10.10.1.6 -U coinops -d coinops_db -c "SELECT count(*) FROM exchange_rates;"
   ```

## Scaling and Logs

- **View Logs**: `docker compose logs -f [service_name]`
- **Rebuild Proxy** (after code changes): `docker compose up -d --build proxy`
- **Stop All**: `docker compose down` (To wipe data: `docker compose down -v`)

---

## Notes
- **Hot Reload**: The Frontend and History services have volumes mounted in `docker-compose.yml`. Changes to Python code will reflect instantly.
- **Proxy Rebuild**: Since the Proxy (Go) is compiled, a rebuild is required for changes to take effect.