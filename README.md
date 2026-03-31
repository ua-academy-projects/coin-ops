# coin-ops

A service for viewing live currency exchange rates and their history.

## Description

This project displays official currency exchange rates from the National Bank of Ukraine (NBU).
Users can view the current rates and browse the history of previously fetched data.

## Architecture
```
Browser → VM1 Flask → VM2 Go Proxy → NBU API
                                    ↓
                          VM3 History Service → PostgreSQL
```

## VMs and Services

| VM | IP | Service | Port |
|----|----|---------|------|
| VM1 | 192.168.56.101 | Web UI (Flask) | 5000 |
| VM2 | 192.168.56.102 | API Proxy (Go) | 8080 |
| VM3 | 192.168.56.103 | History Service (Python) + PostgreSQL | 5001 |
| VM4 | 192.168.56.104 | RabbitMQ (in progress) | — |

## Tech Stack

- **Python + Flask** — web UI
- **Go** — proxy service between UI and external API
- **Python + psycopg2** — history service
- **PostgreSQL** — database for storing rate history
- **RabbitMQ** — message queue (in progress)

## Data Source

NBU Open API: https://bank.gov.ua/ua/open-data/api-dev

Endpoint used:
```
GET https://bank.gov.ua/NBUStatService/v1/statdirectory/exchange?json
```

## How to Run

### VM1 — Flask UI
```bash
cd frontend
source venv/bin/activate
python3 app.py
```

### VM2 — Go Proxy
```bash
cd proxy
go run main.go
```

### VM3 — History Service
```bash
cd consumer
source venv/bin/activate
python3 consumer.py
```

## Service Responsibilities

- **VM1 Flask** — renders the UI, fetches current rates from the proxy, fetches history from the history service
- **VM2 Go Proxy** — receives requests from Flask, fetches data from NBU API, forwards normalized data to the history service asynchronously
- **VM3 History Service** — receives rate data from the proxy, stores it in PostgreSQL, exposes historical data via REST API

## Blockers and Workarounds

| Blocker | Workaround |
|---------|------------|
| Ubuntu 24.04 blocks pip install without venv | Used `python3 -m venv` for isolated environments |
| `dhclient` not available on Ubuntu 24.04 | Set static IPs manually via `ip addr add` and persisted with netplan |
| `permission denied` for PostgreSQL table | Granted privileges via `GRANT ALL PRIVILEGES ON ALL TABLES` |
| GitHub password auth deprecated | Used Personal Access Token instead of password |
| Git push rejected due to remote changes | Used `git pull --rebase` before pushing |