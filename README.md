# Coin-Ops

**UAH exchange rate tracker** — a multi-service application that fetches live currency rates from the [National Bank of Ukraine open API](https://bank.gov.ua/ua/open-data/api-dev), displays them in a web interface, persists historical data asynchronously via a message queue, and provides charts for trend analysis.

Built as part of the [SoftServe DevOps Academy](https://github.com/ua-academy-projects) internship programme.

---

## Table of Contents

- [Features](#features)
- [Architecture](#architecture)
- [Tech Stack](#tech-stack)
- [Prerequisites](#prerequisites)
- [Quick Start (Local Development)](#quick-start-local-development)
- [Services](#services)
  - [UI](#ui)
  - [API Proxy](#api-proxy)
  - [History Service](#history-service)
- [API Reference](#api-reference)
- [Configuration](#configuration)
- [Database Schema](#database-schema)
- [Infrastructure & Deployment](#infrastructure--deployment)
  - [Vagrant (Local VMs)](#vagrant-local-vms)
  - [Ansible (Automated Provisioning)](#ansible-automated-provisioning)
  - [Manual Deployment](#manual-deployment)
- [Troubleshooting](#troubleshooting)
- [Roadmap](#roadmap)
- [Contributing](#contributing)
- [License](#license)

---

## Features

- **Current Rates** — live UAH exchange rates for 40+ currencies, filterable by currency code.
- **Favourites** — pin frequently watched currencies; selections persist via cookies.
- **Currency Search** — instant search across the rates table.
- **Historical Data** — browse past rates with flexible time-range filters (7d / 30d / 90d / 6m / 1y / all).
- **Charts** — interactive line charts for visual trend analysis powered by Chart.js.
- **Rate Delta** — automatic calculation of day-over-day change (absolute and percentage).
- **Asynchronous Pipeline** — rates are published to RabbitMQ on first fetch of a new business day and consumed by the history service, avoiding duplicate writes.
- **Resilient Connectivity** — both Go services implement exponential-backoff reconnect loops for RabbitMQ, starting cleanly even if the broker is unavailable.
- **VM-Isolated Deployment** — each component runs on its own Ubuntu 24.04 Server VM, provisioned with Vagrant and automated via Ansible.

---

## Architecture

```mermaid
flowchart LR
    User[👤 User]
    UI["Web UI\n(Flask + Jinja2)\nport 5000"]
    Proxy["API Proxy\n(Go)\nport 8000"]
    NBU["NBU API\n(bank.gov.ua)"]
    MQ["RabbitMQ\nport 5672"]
    History["History Service\n(Go)\nport 8001"]
    DB[("PostgreSQL\nport 5432")]

    User --> UI
    UI -- "GET /rates" --> Proxy
    Proxy -- "fetch today's rates" --> NBU
    NBU -- "JSON response" --> Proxy
    Proxy -- "filtered rates" --> UI
    Proxy -- "publish rates.fetched\n(new date only)" --> MQ
    MQ -- "consume" --> History
    History -- "INSERT / UPSERT" --> DB
    UI -- "GET /history" --> History
    History -- "historical records" --> UI
```

### Data Flow

1. The **user** opens the UI and requests current rates.
2. The **UI** (Flask) forwards the request to the **API Proxy**.
3. The **API Proxy** checks its in-memory cache (1-hour TTL). On a cache miss it tries the **History Service** first; if that fails, it falls back to the **NBU API**.
4. If the fetched rate date is new, the proxy **publishes** a `rates.fetched` message to **RabbitMQ**.
5. The **History Service** consumes the message, parses the rate batch, and **upserts** each record into **PostgreSQL** within a single transaction.
6. The UI's History and Charts tabs query the History Service directly.

---

## Tech Stack

| Layer | Technology | Rationale |
|---|---|---|
| Frontend / BFF | Python 3.11+ · Flask 3.1 · Jinja2 | Scripted language (per spec) |
| API Proxy | Go 1.22+ · net/http · amqp091-go | Compiled language (per spec) |
| History Service | Go 1.22+ · net/http · lib/pq · amqp091-go | Compiled, same toolchain as proxy |
| Message Queue | RabbitMQ 3.13+ | Durable queue, management UI |
| Database | PostgreSQL 16+ | Relational, UPSERT support |
| Charts | Chart.js (CDN) | Lightweight, zero-build charting |
| Provisioning | Vagrant · Ansible | VM lifecycle and config management |

---

## Prerequisites

| Tool | Minimum Version | Purpose |
|---|---|---|
| [Go](https://go.dev/dl/) | 1.22 | Build api-proxy and history-service |
| [Python](https://www.python.org/downloads/) | 3.11 | Run the UI |
| [PostgreSQL](https://www.postgresql.org/download/) | 16 | History persistence |
| [RabbitMQ](https://www.rabbitmq.com/download.html) | 3.13 | Message queue |
| [Vagrant](https://www.vagrantup.com/downloads) | 2.4 | *(optional)* Local VM provisioning |
| [Ansible](https://docs.ansible.com/ansible/latest/installation_guide/) | 2.15 | *(optional)* Automated deployment |

---

## Quick Start (Local Development)

> **Note:** Ensure PostgreSQL and RabbitMQ are running locally before starting the services. The api-proxy will start without RabbitMQ (publishing is skipped gracefully), and it can operate without the history-service (it falls back to NBU directly).

### 1. Database Setup

```bash
# Create user, database, and apply schema
sudo -u postgres psql <<'EOF'
CREATE USER coinops WITH PASSWORD 'coinops';
CREATE DATABASE coinops OWNER coinops;
EOF

psql -U coinops -d coinops -f history-service/schema.sql
```

### 2. History Service

```bash
cd history-service
cp .env.example .env          # adjust if needed
go run .
# → Listening on :8001
```

### 3. API Proxy

```bash
cd api-proxy
cp .env.example .env          # adjust if needed
go run .
# → Listening on :8000
```

### 4. UI

```bash
cd ui
python3 -m venv .venv
source .venv/bin/activate     # Windows: .venv\Scripts\activate
pip install -r requirements.txt
cp .env.example .env          # adjust if needed
python app.py
# → Listening on :5000
```

> **macOS users:** Port 5000 is used by AirPlay Receiver. Set `PORT=5001` in `ui/.env` or disable AirPlay via _System Settings → General → AirDrop & Handoff_.

Open [http://localhost:5000](http://localhost:5000) (or `:5001`) in your browser.

---

## Services

### UI

| | |
|---|---|
| **Language** | Python 3 · Flask · Jinja2 |
| **Entry point** | `ui/app.py` |
| **Default port** | 5000 |

Server-rendered web application with three views:

- **Rates** (`/`) — current exchange rates table with search, filtering, and favourites.
- **History** (`/history`) — tabular historical data with currency multi-select and time-range picker.
- **Charts** (`/charts`) — interactive Chart.js line graphs for selected currencies over time.

User preferences (selected currencies, time ranges, favourites) are persisted in browser cookies.

---

### API Proxy

| | |
|---|---|
| **Language** | Go (stdlib + amqp091-go) |
| **Entry point** | `api-proxy/main.go` |
| **Default port** | 8000 |

Sits between the UI and the NBU external API. Responsibilities:

- **Caching** — in-memory cache with a 1-hour TTL. On cache miss, tries the history service before calling NBU to avoid unnecessary external requests.
- **Publishing** — on the first fetch of a new rate date, publishes a `rates.fetched` JSON message to RabbitMQ. Subsequent requests for the same date are served from cache without publishing.
- **Resilience** — `mqClient` uses a `connectLoop()` goroutine with `NotifyClose` and exponential backoff (1 s → 30 s cap) to handle broker disconnects transparently.

---

### History Service

| | |
|---|---|
| **Language** | Go (stdlib + lib/pq + amqp091-go) |
| **Entry point** | `history-service/main.go` |
| **Default port** | 8001 |

Dual-role service:

- **Consumer** — reads `rates.fetched` messages from RabbitMQ, parses the rate batch, and upserts each record into PostgreSQL within a single transaction. Uses `ON CONFLICT (code, rate_date) DO UPDATE` for idempotency.
- **HTTP API** — exposes `GET /history` with filtering by currency codes, time range, and result limit.
- **Resilience** — consumer reconnects with exponential backoff on broker disconnect; the HTTP server remains available regardless.

---

## API Reference

### API Proxy — `http://localhost:8000`

| Method | Endpoint | Query Parameters | Description |
|---|---|---|---|
| `GET` | `/health` | — | Returns `{"status":"ok"}` |
| `GET` | `/rates` | `cc` *(optional)* — currency code, e.g. `USD` | All current NBU exchange rates, optionally filtered |

**Example:**

```bash
curl "http://localhost:8000/rates?cc=USD"
```

```json
[
  {
    "code": "USD",
    "name": "Долар США",
    "rate": 41.2899,
    "date": "13.04.2026"
  }
]
```

### History Service — `http://localhost:8001`

| Method | Endpoint | Query Parameters | Description |
|---|---|---|---|
| `GET` | `/health` | — | Returns `{"status":"ok"}` |
| `GET` | `/history` | `cc` — comma-separated codes, e.g. `USD,EUR` | Historical rate records |
| | | `range` — `7d` · `30d` *(default)* · `90d` · `6m` · `1y` · `all` | Time window |
| | | `limit` — integer, 1–5000 *(default 500)* | Max results |

**Example:**

```bash
curl "http://localhost:8001/history?cc=USD,EUR&range=7d&limit=10"
```

```json
[
  {
    "id": 42,
    "code": "USD",
    "name": "Долар США",
    "rate": 41.2899,
    "rate_date": "13.04.2026",
    "fetched_at": "2026-04-13T12:00:00Z"
  }
]
```

---

## Configuration

Each service reads configuration from environment variables. Copy the `.env.example` file in each service directory and adjust values for your environment.

### UI (`ui/.env`)

| Variable | Default | Description |
|---|---|---|
| `PORT` | `5000` | Listen port (use `5001` on macOS) |
| `API_PROXY_URL` | `http://localhost:8000` | API Proxy base URL |
| `HISTORY_SERVICE_URL` | `http://localhost:8001` | History Service base URL |

### API Proxy (`api-proxy/.env`)

| Variable | Default | Description |
|---|---|---|
| `PORT` | `8000` | Listen port |
| `CORS_ORIGINS` | `http://localhost:5000` | Comma-separated allowed origins |
| `RABBITMQ_URL` | `amqp://guest:guest@localhost:5672/` | RabbitMQ connection string |
| `HISTORY_SERVICE_URL` | `http://localhost:8001` | History Service base URL (used for cache warm-up) |

### History Service (`history-service/.env`)

| Variable | Default | Description |
|---|---|---|
| `PORT` | `8001` | Listen port |
| `CORS_ORIGINS` | `http://localhost:5000` | Comma-separated allowed origins |
| `DATABASE_URL` | `postgres://coinops:coinops@localhost:5432/coinops?sslmode=disable` | PostgreSQL connection string |
| `RABBITMQ_URL` | `amqp://guest:guest@localhost:5672/` | RabbitMQ connection string |

---

## Database Schema

The history service uses a single table. Apply the schema with:

```bash
psql -U coinops -d coinops -f history-service/schema.sql
```

```sql
CREATE TABLE IF NOT EXISTS rate_history (
    id          BIGSERIAL PRIMARY KEY,
    code        VARCHAR(10)    NOT NULL,
    name        TEXT           NOT NULL,
    rate        NUMERIC(18,6)  NOT NULL,
    rate_date   VARCHAR(20)    NOT NULL,
    fetched_at  TIMESTAMPTZ    NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_rate_history_code       ON rate_history (code);
CREATE INDEX IF NOT EXISTS idx_rate_history_fetched_at ON rate_history (fetched_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS idx_rate_history_code_date ON rate_history (code, rate_date);
```

The unique index on `(code, rate_date)` enables idempotent upserts — duplicate messages from RabbitMQ are handled gracefully.

---

## Infrastructure & Deployment

The application is designed for **VM-based isolation** on Ubuntu 24.04 Server. Each component runs on a dedicated VM.

### VM Layout

| VM | Hostname | Static IP | Service | Default Port(s) |
|---|---|---|---|---|
| VM 1 | `web-ui` | `192.168.56.10` | Flask UI + nginx | 80 (public), 5000 (internal) |
| VM 2 | `api-proxy` | `192.168.56.11` | Go API Proxy | 8000 |
| VM 3 | `db-server` | `192.168.56.12` | PostgreSQL | 5432 |
| VM 4 | `msg-queue` | `192.168.56.13` | RabbitMQ | 5672, 15672 (mgmt) |
| VM 5 | `history-svc` | `192.168.56.14` | Go History Service | 8001 |

```mermaid
flowchart TB
    subgraph Host["Host Machine"]
        subgraph VM1["VM 1 — web-ui\n192.168.56.10"]
            nginx["nginx :80"]
            flask["Flask :5000"]
            nginx --> flask
        end

        subgraph VM2["VM 2 — api-proxy\n192.168.56.11"]
            proxy["Go api-proxy :8000"]
        end

        subgraph VM3["VM 3 — db-server\n192.168.56.12"]
            pg[("PostgreSQL :5432")]
        end

        subgraph VM4["VM 4 — msg-queue\n192.168.56.13"]
            mq["RabbitMQ :5672\nmgmt :15672"]
        end

        subgraph VM5["VM 5 — history-svc\n192.168.56.14"]
            history["Go history-service :8001"]
        end
    end

    NBU["NBU API (public)"]

    flask --> proxy
    flask --> history
    proxy --> NBU
    proxy -->|"AMQP"| mq
    mq -->|"consume"| history
    history -->|"SQL"| pg
```

---

### Vagrant (Local VMs)

Vagrant provisions all five VMs using the `bento/ubuntu-24.04` box with VMware Desktop.

```bash
cd vagrant
vagrant up          # Create and boot all 5 VMs
vagrant status      # Verify all are running
vagrant ssh web-ui  # SSH into a specific VM
```

The [Vagrantfile](vagrant/Vagrantfile) defines per-VM CPU and RAM allocations:

| VM | CPUs | RAM |
|---|---|---|
| web-ui | 1 | 1 GB |
| api-proxy | 1 | 512 MB |
| msg-queue | 1 | 1.5 GB |
| history-svc | 2 | 2 GB |
| db-server | 2 | 2 GB |

---

### Ansible (Automated Provisioning)

Ansible automates the full deployment across all Vagrant VMs. See [`ansible/README.md`](ansible/README.md) for detailed instructions.

**Quick start:**

```bash
# Install required collections
ansible-galaxy collection install \
  ansible.posix community.general community.postgresql community.rabbitmq

# Set required secrets
export DB_PASSWORD=<your-db-password>
export RABBIT_MQ_PASSWORD=<your-rabbitmq-password>
export HOST_IP=<your-lan-ip>/32    # for RabbitMQ management UI access

# Deploy everything
cd ansible
ansible-playbook site.yml
```

**Playbook execution order** (dependency-aware):

1. `db-server.yml` — PostgreSQL installation, user/database creation, schema application
2. `msg-queue.yml` — RabbitMQ installation, user creation, firewall rules
3. `history-service.yml` — Go build, systemd unit, connection to DB and MQ
4. `api-proxy.yml` — Go build, systemd unit, connection to MQ and history-service
5. `web-ui.yml` — Python venv, Flask app, nginx reverse proxy, systemd unit

To deploy a single service:

```bash
ansible-playbook playbooks/api-proxy.yml
```

---

## Contributing

1. Fork the repository.
2. Create a feature branch: `git checkout -b feature/my-feature`.
3. Commit your changes: `git commit -m 'Add my feature'`.
4. Push to the branch: `git push origin feature/my-feature`.
5. Open a Pull Request.

Please document any environment-specific blockers or workarounds you encounter.

---

## License

This project is licensed under the [MIT License](LICENSE).

Copyright © 2026 [UA Academy Projects](https://github.com/ua-academy-projects).

---

## Data Source

All exchange rate data is sourced from the **National Bank of Ukraine**:

```
https://bank.gov.ua/NBUStatService/v1/statdirectory/exchange?json
```

No API key is required. Rates are published each business day; the `exchangedate` field reflects the business date the rate applies to. See the [NBU API documentation](https://bank.gov.ua/ua/open-data/api-dev) for details.
