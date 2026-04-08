# Polymarket Intelligence Dashboard (Coin Ops)

## Project Overview

"Coin Ops" is a polyglot, microservice-based application providing a Polymarket Intelligence Dashboard. It aggregates live market data, whale positions, and external cryptocurrency prices (from CoinGecko and NBU) into a high-performance web dashboard.

The architecture is designed across three nodes/services communicating via a message broker (RabbitMQ):
*   **Proxy Service (Go):** A stateless HTTP bridge that serves the UI, fetches external data, manages session state in Redis, caches results, and pushes normalized market/price events to RabbitMQ.
*   **History Consumer (Python/pika):** A reliable AMQP consumer that reads messages from RabbitMQ and stores market/price snapshots into a PostgreSQL database.
*   **History API (Python/FastAPI):** A read-only REST API exposing the stored time-series data from PostgreSQL to the frontend.
*   **Web UI (React/Vite):** A dark, data-dense single-page dashboard for visualizing the live markets and historical charts. (There is also a legacy Vanilla JS implementation).
*   **Infrastructure (Terraform & Ansible):** Scripts to provision Hyper-V VMs and configure the underlying services (RabbitMQ, Redis, PostgreSQL).

## Building and Running

The project requires external services to be running (PostgreSQL, RabbitMQ, Redis). These can be provisioned using the provided Terraform and Ansible configurations.

### 1. Proxy Service (Go)
Located in the `proxy/` directory.
*   **Run locally:** `make run` or `go run .`
*   **Build for Linux:** `make build`
*   *Note: Requires `REDIS_URL` and a running RabbitMQ instance.*

### 2. History API & Consumer (Python)
Located in the `history/` directory. Requires Python 3.
*   **Install Dependencies:** `pip install -r requirements.txt`
*   **Run Consumer:** `python consumer.py`
*   **Run API:** `uvicorn main:app --reload` (Runs on port 8000 by default)

### 3. Web UI (React)
Located in the `ui-react/` directory.
*   **Install Dependencies:** `npm install`
*   **Run Development Server:** `npm run dev` (Runs on port 3000)
*   **Build for Production:** `npm run build`

## Development Conventions

*   **Service Decoupling:** The UI and Proxy Service **never** write directly to the PostgreSQL database. All data flows asynchronously through the RabbitMQ `market_events` queue to the Python consumer.
*   **Timezone Safety:** `TIMESTAMPTZ` is used strictly in PostgreSQL and across services to avoid timezone-related data corruption across VMs.
*   **Database Schema Management:** The Python `consumer.py` takes ownership of database schema initialization (`CREATE TABLE IF NOT EXISTS`).
*   **State & Caching:** Redis is used exclusively for ephemeral user session state (`session:<uuid>`, 24h TTL). Data caching is handled in-memory by the Go Proxy Service using thread-safe structures (`sync.RWMutex`).
*   **Idempotency:** The Python consumer is designed to be idempotent (`ON CONFLICT DO NOTHING`) to handle potential RabbitMQ message redeliveries gracefully.