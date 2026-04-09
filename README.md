# Coin-Ops

A microservices-based financial data aggregator that fetches, normalizes, and stores real-time exchange rates for Fiat and Cryptocurrencies.<br><br>
Coin-Ops is designed with an infrastructure-first approach to demonstrate a modern hybrid architecture. It pulls data from public sources (NBU, CoinGecko) via a Go-based proxy, processes it asynchronously, and serves it through a Python/Flask web interface.

## Architecture
The system uses a **Hybrid Infrastructure** model:
*   **Docker Compose (Local/WSL)**: Applications (Frontend, Proxy, History Service) and Infrastructure (RabbitMQ, Redis) run in lightweight containers.
*   **Vagrant & Ansible (VM)**: The PostgreSQL database remains on a dedicated, secure virtual machine for stateful persistence.

### Components:
*   **Frontend**: Python / Flask web interface with Redis caching.
*   **Proxy service**: Go-based gateway that fetches and normalizes data from 3rd-party APIs.
*   **History service**: Python consumer that handles MQ events and exposes the History API.
*   **Message queue**: RabbitMQ broker for asynchronous updates.
*   **Database**: PostgreSQL instance on a managed Vagrant VM.

## How to use?

### Prerequisites
*   [Docker Desktop](https://www.docker.com/products/docker-desktop/)
*   [Vagrant](https://developer.hashicorp.com/vagrant)
*   VMware Workstation or VirtualBox

### Quick Start (Infrastructure First)

1.  **Clone the repository**:
    ```bash
    git clone https://github.com/ua-academy-projects/coin-ops.git
    cd coin-ops
    ```

2.  **Setup Configuration**:
    Create your local environment file from the template in the `infra/` folder.
    ```bash
    cp infra/.env.example infra/.env
    # Edit infra/.env and fill in the database password
    ```

3.  **Deploy Database VM**:
    ```bash
    cd infra
    vagrant up
    ```

4.  **Launch Docker Stack**:
    ```bash
    docker compose up -d
    ```

## Configuration & Secrets
We strictly follow the **"No Hardcode"** policy:
-   **Local Development**: Managed via `infra/.env` (using `.env.example` as a template).
-   **Secrets**: Database/MQ passwords are encrypted using **Ansible Vault** for VM provisioning.
-   **Infrastructure Info**: All IPs, Ports, and API URLs are extracted into variables and can be modified without changing the source code.

## Documentation
*   **[Runbook](docs/runbook.md)**: Operational guides, port matrices, and health check commands.
*   **[Blockers & Workarounds](docs/blockers.md)**: Troubleshooting history and known issues during Docker migration.

---

## Progress & Roadmap
*   **Phase 1 — Usability**: ✅ Improved UI, human-readable formats, search by code/name.
*   **Phase 2 — Infrastructure Evolution**: ✅ RabbitMQ integration, Redis implementation, Ansible migration.
*   **Phase 3 — Containerization**: ✅ Docker migration, Decoupling configuration, Multi-stage builds.
*   **Phase 4 — Security**: ⏳ Firewall hardening, automated TLS, advanced secrets management.
