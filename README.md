# Coin-Ops

A microservices-based financial data aggregator that fetches, normalizes, and stores real-time exchange rates for Fiat and Cryptocurrencies.<br><br>
Coin-Ops is designed with an infrastructure-first approach to demonstrate a robust microservices architecture. It pulls data from public sources (NBU, CoinGecko) via a Go-based proxy, processes it asynchronously, and serves it through a Python/Flask web interface. The entire environment is automated and provisioned across isolated virtual machines.

## Architecture
System runs on 5 virtual machines configured via Vagrant and Bash scripts.
* **VM1 (10.10.1.2) - Frontend**: Python / Flask web interface.
* **VM2 (10.10.1.3) - Proxy service**: Go API gateway, fetches and normalizes data from 3rd-party APIs.
* **VM3 (10.10.1.4) - History service**: Python service that consumes MQ events and exposes History API.
* **VM4 (10.10.1.5) - Message queue**: RabbitMQ broker.
* **VM5 (10.10.1.6) - Database**: PostgreSQL instance storing historical exchange rates.

## How to use?
### Prerequisites
Ensure you have the following installed on your host machine before starting:
* [Vagrant](https://developer.hashicorp.com/vagrant)
* VMware Workstation (or VirtualBox, but you need to specify compatible Vagrant box)

### Installation & Run

1. Clone the repository:
   ```bash
   git clone <your-repo-link>
   cd coin-ops
2. Provision and start the infrastructure:
    ```Bash
    vagrant up
    # or run the batch script for parallel deployment of each VM:
    ./launch.sh
## To-Do List
* Phase 1 - Usability:
  * [ ] Better UI
    * [ ] Convert currency to a human-readable format
    * [ ] Convert time to a human-readable format
  * [ ] Show only the most popular fiats / coins
  * [ ] Search by code (UAH / USD / BTC / etc) or name if possible (Долар США / Євро / Etherum / etc) - need to fetch list of coin names / codes
  * [ ] Convert coins to UAH for general list
  * [ ] Convert any-to-any fiat / coin (but that would be more of a currency converter than a list)<br>
  * [ ] Reworking the logic of the “History” tab
* Phase 2 - Infrastructure Evolution:
  * [ ] RabbitMQ implementing
  * [ ] Redis implementing (caching and remembering user preferences)
  * [ ] Migrate provisioning to Terraform / Ansible
  * [ ] Security work (minimum permissions, firewall, secrets for credentials, etc)

## Phase A (Implemented): Async Flow via RabbitMQ

### Service responsibilities
- **VM1 Frontend (`services/frontend`)**
  - `GET current` from Proxy (`/api/v1/rates`)
  - `GET history` from History Service (`/api/v1/history`)
- **VM2 Proxy (`services/proxy`)**
  - Fetch NBU + CoinGecko
  - Normalize payload
  - Return live response to UI
  - Publish `rates.snapshot.v1` event to RabbitMQ (best-effort, non-blocking for UI)
- **VM3 History Service (`services/worker/worker.py`)**
  - Consume MQ events from `coinops.history`
  - Persist rows to PostgreSQL
  - Expose history API endpoint (`GET /api/v1/history`)
- **VM4 RabbitMQ (`10.10.1.5`)**
  - RabbitMQ broker (AMQP 5672)
- **VM5 PostgreSQL (`10.10.1.6`)**
  - PostgreSQL (default 5432)

### Message contract (v1)
Proxy publishes JSON envelope:
- `event_id` (uuid)
- `event_type` = `rates.snapshot.v1`
- `created_at` (UTC)
- `source` = `proxy`
- `data` = previous `RatesResponse` (`rates`, `fetched_at`, `errors`)

### Environment files
- Proxy: `services/proxy/proxy.env`
- History Service: `services/worker/worker.env`
- Frontend: `services/frontend/frontend.env`

### Basic run notes (systemd)
After updating env files:
```bash
sudo systemctl daemon-reload
sudo systemctl restart proxy worker frontend
sudo systemctl status proxy worker frontend
```

### Smoke-check (acceptance criteria)
1) Current data via proxy:
```bash
curl -sS http://10.10.1.3:8080/api/v1/rates | jq '.rates | length'
```
2) Event appears in queue (length may fluctuate quickly if consumer is active):
```bash
rabbitmqctl list_queues name messages consumers
```
3) History API works:
```bash
curl -sS "http://10.10.1.4:8090/api/v1/history?limit=5" | jq '.count'
```
4) PostgreSQL has records:
```bash
psql -h 10.10.1.6 -U coinops -d coinops_db -c "select count(*) from exchange_rates;"
```