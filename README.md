# Coin-Ops

Coin-Ops is a small distributed system built as a Polymarket intelligence dashboard. It combines live market data, crypto prices, whale activity, historical storage, and automated infrastructure into one project.

The point of the project is not just to show a frontend. It is meant to demonstrate:

- service separation instead of a monolith
- asynchronous ingestion through RabbitMQ
- historical persistence in PostgreSQL
- ephemeral session state in Redis
- VM provisioning and deployment with Terraform and Ansible
- a UI that consumes both live and historical data paths

## What It Does

The application shows:

- live Polymarket market snapshots
- BTC, ETH, and USD/UAH prices
- whale positions from Polymarket data sources
- historical market charts backed by PostgreSQL
- session-aware UI state via Redis

At a high level, the browser does not talk to PostgreSQL directly and it does not write business data anywhere. The Go proxy fetches and normalizes external data, publishes snapshots into RabbitMQ, and a separate Python consumer persists those events into PostgreSQL. A separate Python API exposes read-only history back to the UI.

## Architecture

### Main Components

`ui-react/`
Modern React/Vite frontend. This is the main UI.

`ui/`
Legacy static UI version.

`proxy/`
Go service that acts as the live-data gateway. It fetches current Polymarket markets, whale data, and external prices. It also manages Redis-backed UI session state.

`history/consumer.py`
Python RabbitMQ consumer that persists market and price snapshots into PostgreSQL.

`history/main.py`
Python FastAPI service that exposes historical data from PostgreSQL.

`terraform/`
Infrastructure definitions for VM/network provisioning.

`ansible/`
Provisioning and deployment automation for the application stack.

## Data Flow

The system has two separate paths: live path and history path.

### Live Path

1. The frontend calls the Go proxy.
2. The proxy fetches current markets, whale positions, and prices from external APIs.
3. The proxy returns normalized live JSON to the UI.

### History Path

1. The proxy publishes market and price events to RabbitMQ.
2. The Python consumer reads those events and stores them in PostgreSQL.
3. The history API reads PostgreSQL and returns time-series data to the UI for chart rendering.

This split is intentional. It avoids tightly coupling UI requests with DB writes and makes the ingestion pipeline easier to reason about.

## Tech Stack

### Frontend

- React 19
- Vite
- TypeScript
- Tailwind CSS
- Recharts

### Backend

- Go 1.21
- Python 3
- FastAPI
- pika
- RabbitMQ
- PostgreSQL
- Redis

### Infra / Ops

- Terraform
- Ansible
- systemd
- nginx
- Hyper-V VMs

## Why It Is Built This Way

This project is intentionally split into services because each part has a different responsibility.

### Go Proxy

The Go service owns fast live reads and normalization. It is a good fit for:

- concurrent HTTP fetching
- low-latency request handling
- in-memory caching
- publishing normalized events

### Python Consumer

The Python consumer owns reliable persistence. It is simpler to keep database writes and queue handling in one focused service than to mix them into the live proxy.

### Python History API

The history API is read-only by design. That makes the flow cleaner:

- write path: queue -> consumer -> database
- read path: history API -> database -> UI

### Redis

Redis stores short-lived user session state only. It is not the system of record for historical market data.

### RabbitMQ

RabbitMQ decouples live ingestion from persistence. If the history writer is slow or temporarily unavailable, the live proxy is not forced to become the DB writer.

## Repository Layout

```text
.
|-- ansible/      # Provisioning and deployment playbooks
|-- docs/         # Supporting architecture and deployment notes
|-- history/      # Python consumer + history API + schema
|-- proxy/        # Go live-data proxy
|-- terraform/    # Infrastructure definitions
|-- ui/           # Legacy static UI
`-- ui-react/     # Main React frontend
```

## Services and Responsibilities

### `proxy/`

Responsibilities:

- fetch current Polymarket markets
- fetch whale data
- fetch BTC/ETH and USD/UAH prices
- return live JSON to the UI
- persist UI session state in Redis
- publish market and price events to RabbitMQ

This service is the live edge of the application.

### `history/consumer.py`

Responsibilities:

- consume RabbitMQ messages
- route messages by type
- insert snapshots into PostgreSQL
- handle reconnects and retries
- keep persistence idempotent

This service is the write path into the database.

### `history/main.py`

Responsibilities:

- expose market history by slug
- expose price history by coin
- expose health endpoint

This service is the read path from PostgreSQL.

### `ui-react/`

Responsibilities:

- render homepage and market views
- fetch live data from the proxy
- fetch chart history from the history API
- show market and price trends
- persist some UI state through the proxy

## External Data Sources

The project depends on public APIs for live inputs.

- Polymarket Gamma API for live market snapshots
- Polymarket Data API for whale-style position data
- CoinGecko for crypto prices
- NBU API for USD/UAH

Because these are external dependencies, the project should be treated as a demo system rather than a guaranteed production-grade data platform.

## Local Development

There are two practical ways to work with this repo:

- run services individually for focused development
- use the VM/infrastructure path for a fuller end-to-end environment

### Frontend

```bash
cd ui-react
npm install
npm run dev
```

Build check:

```bash
npm run lint
npm run build
```

### Go Proxy

```bash
cd proxy
go run .
```

Or:

```bash
make run
```

### Python History Services

```bash
cd history
python -m venv venv
venv\Scripts\activate
pip install -r requirements.txt
python consumer.py
python main.py
```

You will need working RabbitMQ and PostgreSQL connectivity for the history path to function.

## Environment and Configuration

The repo contains:

- `.env.example`
- Ansible inventory and variable files
- service-specific environment usage in deployed systemd units

Important runtime dependencies include:

- RabbitMQ connection URL
- PostgreSQL connection URL
- Redis URL
- proxy/history service ports
- frontend `VITE_PROXY_URL` and `VITE_HISTORY_URL`

Keep secrets out of Git. This project already separates deploy-time configuration from source code.

## Deployment Model

The deployment target is a small three-VM layout.

### Node Roles

`node-01`
- PostgreSQL
- RabbitMQ
- history consumer
- history API

`node-02`
- Go proxy
- Redis

`node-03`
- nginx
- web UI

This is a pragmatic layout for a small demo environment. It is not pretending to be hyperscale; it is showing separation of concerns under realistic resource limits.

## Provisioning and Deployment

### Terraform

Terraform defines the infrastructure side:

- VM-related configuration
- network details
- outputs and variables

### Ansible

Ansible handles:

- package installation
- application sync/deploy
- service environment files
- systemd unit installation
- service restart/reload

This is one of the strongest parts of the project from a DevOps internship perspective, because the project is not just code sitting in folders. It has an actual provisioning and deployment story.

## Health and Operations

Relevant operational paths:

- proxy health endpoint
- history API health endpoint
- systemd service management
- queue-backed ingestion

The project is still a demo system, but it already includes useful operational signals and a deployment model that is easy to explain.

## What Makes This Project Good for a CV

This project shows more than frontend polish.

It demonstrates:

- distributed system thinking
- decoupled data ingestion
- multiple languages used for appropriate reasons
- infrastructure automation
- operational awareness
- state separation between cache, queue, and database

That is stronger than a typical "single web app + Dockerfile" portfolio project.

## Current Limitations

The project still has normal demo-project tradeoffs:

- depends on third-party APIs
- some data quality depends on upstream sources
- charting/history quality is bounded by what has already been ingested
- local developer experience is not yet container-first

These are acceptable tradeoffs for an internship-level systems project, especially since the architecture is explicit and understandable.

## Good Next Steps

If I were continuing this project for demo quality, I would prioritize:

1. Containerize the services cleanly.
2. Add a `docker-compose.yml` for local development.
3. Add one architecture diagram to the README.
4. Tighten the root README screenshots/demo flow.
5. Normalize category handling on the backend instead of the UI.
6. Add a short walkthrough script for interviews.

For containers:

- Go proxy: distroless or another minimal runtime image
- Python services: `python:slim`
- UI: nginx-based static image

## How To Talk About It In Interview

Short version:

"Coin-Ops is a small Polymarket intelligence dashboard built as a distributed system. The Go proxy handles live aggregation and publishes market/price events into RabbitMQ. A Python consumer persists snapshots into PostgreSQL, and a separate FastAPI service exposes read-only time-series data to the React UI. I provision and deploy the stack with Terraform and Ansible across three VMs. The main thing I wanted to show was separation of concerns: live reads, async persistence, historical querying, and infra automation."

That explanation is short, concrete, and defensible.

## Status

The project is already strong enough to be a CV/demo project if:

- the main flows work reliably
- the README is clear
- deployment is reproducible
- the repo stays clean and intentional

At this stage, more value comes from clarity and reliability than from endless UI polishing.
