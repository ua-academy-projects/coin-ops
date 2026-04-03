# coin-ops

A multi-service application that fetches live cryptocurrency and fiat currency rates from public APIs, displays them in a web UI, and persists historical data via an asynchronous message queue.

## Architecture

```
Browser
  │
  ▼
VM1 — nginx (UI)          serves frontend static files
  │   port 8080 (host)    proxies /api/* → VM2
  │
  ▼
VM2 — FastAPI (Proxy)     REST API for the frontend
  │   port 8000 (host)    reads from PostgreSQL (VM5)
  │
  ├── Go api_getter        fetches rates from CoinGecko & NBU APIs
  │                        every 20 min, publishes to RabbitMQ (VM4)
  │
  ▼
VM4 — RabbitMQ (Queue)    fanout exchange "rates"
  │   port 15672 (host)   management UI
  │
  ▼
VM3 — Python consumer     consumes messages from RabbitMQ
  │   (History Service)   inserts records into PostgreSQL (VM5)
  │
  ▼
VM5 — PostgreSQL (DB)     persists all currency rate records
```

## Services

| Service | Directory | Language | Description |
|---|---|---|---|
| Frontend | `frontend/` | HTML / JS / CSS | Single-page UI with live rates and history charts |
| Backend API | `backend/` | Python / FastAPI | Proxy between UI and DB; exposes REST endpoints |
| API Getter | `api_getter/` | Go | Fetches rates from external APIs, publishes to RabbitMQ |
| DB Consumer | `postgre_db/` | Python | Consumes RabbitMQ messages and writes to PostgreSQL |

## Data Sources

- **CoinGecko** — Bitcoin, Ethereum, Solana, Ripple, Cardano, Dogecoin (USD / UAH / EUR)
- **National Bank of Ukraine (NBU)** — Fiat currency rates in UAH

## VM Layout

| VM | Hostname | Private IP | Forwarded Port | Role |
|---|---|---|---|---|
| VM1 | `ui` | 192.168.56.11 | 8080 → 80 | nginx + frontend |
| VM2 | `proxy` | 192.168.56.12 | 8000 → 8000 | FastAPI + Go api_getter |
| VM3 | `history` | 192.168.56.13 | — | Python consumer |
| VM4 | `queue` | 192.168.56.14 | 15672 → 15672 | RabbitMQ |
| VM5 | `db` | 192.168.56.15 | — | PostgreSQL |

## Prerequisites

- [Vagrant](https://www.vagrantup.com/) 2.x
- [VirtualBox](https://www.virtualbox.org/) 7.x
- ~6 GB free RAM (all 5 VMs running simultaneously)
- ~15 GB free disk space

> **Windows users:** Run all Vagrant commands from **PowerShell or CMD** on a local Windows path (e.g. `C:\projects\coin-ops`), not from a WSL path.

## Quick Start

```powershell
# Clone the repository
git clone https://github.com/ua-academy-projects/coin-ops.git
cd coin-ops

# Start all VMs (first run takes ~10 minutes)
vagrant up

# Open the app in your browser
start http://localhost:8080

# RabbitMQ management UI
start http://localhost:15672
# credentials: coinops / coinops123
```

## Starting Individual VMs

```bash
vagrant up db        # start only PostgreSQL
vagrant up queue     # start only RabbitMQ
vagrant up history   # start only the consumer
vagrant up proxy     # start only the backend + api_getter
vagrant up ui        # start only the frontend
```

## Useful Commands

```bash
vagrant ssh proxy           # SSH into a VM
vagrant halt                # stop all VMs (preserves state)
vagrant destroy -f          # delete all VMs
vagrant provision proxy     # re-run provisioning on a VM
vagrant status              # show status of all VMs
```

## API Endpoints

Base URL (via nginx proxy): `http://localhost:8080`  
Direct backend URL: `http://localhost:8000`

| Method | Path | Description |
|---|---|---|
| GET | `/api/currencies` | List all available currency pairs |
| GET | `/api/rates/latest` | Latest rate for each currency |
| GET | `/api/rates/history/{code}` | Historical rates (params: `base`, `limit`) |

### Example

```bash
# Latest rates
curl http://localhost:8080/api/rates/latest

# Bitcoin history (last 50 records, base UAH)
curl "http://localhost:8080/api/rates/history/BTC?base=UAH&limit=50"
```

## Environment Variables

| Variable | Default | Used by |
|---|---|---|
| `DATABASE_URL` | `postgresql://coinops:coinops123@localhost:5432/coinops` | backend, consumer |
| `RABBITMQ_URL` | `amqp://coinops:coinops123@localhost:5672/` | api_getter, consumer |
| `FETCH_INTERVAL` | `20m` | api_getter |

## Database Schema

```sql
CREATE TABLE currency_rates (
    id            BIGSERIAL      PRIMARY KEY,
    currency_code VARCHAR(20)    NOT NULL,
    currency_name VARCHAR(100),
    source        VARCHAR(50)    NOT NULL,
    rate          NUMERIC(24, 8) NOT NULL,
    base_currency VARCHAR(10)    NOT NULL DEFAULT 'USD',
    fetched_at    TIMESTAMPTZ    NOT NULL DEFAULT NOW()
);
```

## Project Structure

```
coin-ops/
├── Vagrantfile          # multi-VM provisioning
├── frontend/
│   ├── index.html       # single-page app shell
│   ├── app.js           # fetch logic + Chart.js charts
│   └── styles.css
├── backend/
│   ├── app.py           # FastAPI application
│   └── requirements.txt
├── api_getter/
│   ├── main.go          # Go rate fetcher + RabbitMQ publisher
│   └── go.mod
└── postgre_db/
    ├── consumer.py      # RabbitMQ → PostgreSQL consumer
    ├── init.sql         # database schema
    └── requirements.txt
```
