 # CoinOps — Currency & Crypto Rates Monitoring System

A microservices application that fetches currency exchange rates from public APIs, stores historical data asynchronously via a message queue, and displays current and historical rates through a web UI.

Built as a DevOps internship iteration project, focused on multi-VM deployment, inter-service communication, infrastructure automation, and containerization.

The project supports two deployment modes:
- **VM-based** — four Ubuntu 24.04 VMs with systemd-managed services and Ansible automation
- **Docker-based** — single host running the full stack via Docker Compose

---

## Architecture

```
                    ┌──────────────┐
                    │     User     │
                    └──────┬───────┘
                           │
                           ▼
              ┌────────────────────────┐
              │   Web UI (Flask)       │
              └─────┬──────────────┬───┘
                    │              │
        current data│              │history
                    ▼              ▼
        ┌───────────────────┐  ┌──────────────────────┐
        │ Go API Proxy      │  │ History Service      │
        │                   │  │ + PostgreSQL         │
        └────┬────────┬─────┘  │ + Redis              │
             │        │        └────────▲─────────────┘
             │        │ publish          │ consume
             │        ▼                  │
             │   ┌──────────────────────┴─┐
             │   │ RabbitMQ               │
             │   └────────────────────────┘
             │
             ▼
       ┌──────────┐
       │ NBU API  │
       │ CoinGecko│
       └──────────┘
```

### Data flow

1. User opens the UI in a browser → Flask renders the page
2. Flask requests current rates from the Go Proxy
3. Proxy fetches data from NBU API (fiat) and CoinGecko (crypto)
4. Proxy returns the response to Flask AND publishes a normalized message to RabbitMQ
5. The Consumer service reads messages from RabbitMQ and stores them in PostgreSQL
6. When the user opens the History page, Flask requests historical records from the Consumer's HTTP API
7. User favorites (selected currencies) are stored in Redis for cross-session persistence

---

## Tech stack

- **UI:** Python 3 + Flask + Jinja2 + vanilla JavaScript + Chart.js
- **Proxy:** Go (standard library + amqp091-go for RabbitMQ)
- **Consumer / History API:** Python 3 + Flask + pika + psycopg2 + redis-py
- **Storage:** PostgreSQL 16 (historical records), Redis 7 (user preferences)
- **Message broker:** RabbitMQ 3 with management plugin
- **Process management:** systemd (VM mode) or Docker (container mode)
- **Infrastructure automation:** Bash setup scripts + Ansible playbooks
- **Containerization:** Docker + Docker Compose with multi-stage builds and Alpine base images
- **Public APIs:** [bank.gov.ua](https://bank.gov.ua/NBUStatService/v1/statdirectory/exchange?json) (NBU), [coingecko.com](https://www.coingecko.com/en/api) (crypto)

---

## Service responsibilities

### Flask UI (`frontend/app.py`)
- Serves the main page (`/`) with current rates and the history page (`/history`)
- Calls the Go proxy to fetch live data
- Calls the Consumer to fetch historical data and user favorites
- Forwards favorite-saving requests from the browser to the Consumer (`/api/favorites`)
- Backend URLs are read from `PROXY_URL` and `CONSUMER_URL` environment variables (with sensible defaults for the VM layout)

### Go Proxy (`proxy/main.go`)
- Exposes `/rates` (NBU fiat) and `/crypto` (CoinGecko) HTTP endpoints
- Fetches data from the upstream APIs on demand
- Publishes normalized rate events to the `rates` queue in RabbitMQ on every fetch
- Has a background `autoRefresh` goroutine that publishes fresh rates every 5 minutes regardless of user activity
- Implements connection retry logic — keeps reconnecting if RabbitMQ is unavailable at startup
- RabbitMQ URL and listen port are read from `RABBITMQ_URL` and `PORT` environment variables

### Consumer + History API (`consumer/consumer.py`)
- Consumer thread listens on the `rates` queue and inserts records into the `rates` table in PostgreSQL
- Flask HTTP API exposes:
  - `GET /history?hours=N` — historical records for the last N hours
  - `GET /favorites` — list of user-favorited currency codes (from Redis)
  - `POST /favorites` — replaces the favorites set in Redis
- Has retry logic for the RabbitMQ connection (5-second backoff)
- All connection settings (DB, RabbitMQ, Redis) are read from environment variables

### RabbitMQ
- Single durable queue `rates`
- Custom user `coinops`
- Management UI on port 15672 for queue inspection

---

## Functional features

### Current rates page (`/`)
- Live ticker with popular currencies
- Top cards (USD, EUR, BTC, ETH) with 24h change indicator
- Two tables: NBU fiat currencies and crypto, with search and column sorting
- Sparkline trend (mini SVG chart) per currency, colored by direction
- Per-row 24h change percentage
- Star (★) favoriting persisted in Redis
- Three-field currency converter (amount → from → to) supporting fiat-fiat, fiat-crypto and crypto-crypto cross conversions through UAH as the pivot
- Market clocks showing open/closed status for Kyiv, London (LSE), New York (NYSE), Tokyo (TSE)

### History page (`/history`)
- Stat cards: maximum, minimum, average, volatility for selected currencies
- Type filter: All / NBU fiat / Crypto
- Period filter: 6h / Day / Week / Month / All
- Currency pills grouped into Favorites (★) / Popular / All others
- Line chart with linear/logarithmic Y-axis toggle and area fill toggle
- CSV export of the currently filtered data
- Records table with delta (▲ / ▼) versus the previous record per currency, search, and unit display

---

# Deployment

CoinOps can be deployed in two ways. Pick whichever fits the situation.

## Mode A — VM-based deployment (4 VMs)

This is the original layout used during early iterations. Each service runs on a dedicated Ubuntu 24.04 Server VM under systemd.

### VM layout

| VM  | IP              | Role                          | Services                           |
|-----|-----------------|-------------------------------|------------------------------------|
| VM1 | 192.168.56.101  | Web UI                        | Flask (`flask.service`)            |
| VM2 | 192.168.56.102  | API Proxy                     | Go proxy (`proxy.service`)         |
| VM3 | 192.168.56.103  | History service + storage     | Consumer, PostgreSQL, Redis        |
| VM4 | 192.168.56.104  | Message broker                | RabbitMQ + management plugin       |

All VMs are networked via a VirtualBox host-only network.

### Setup — Bash scripts

On each VM:

```bash
git clone https://github.com/ua-academy-projects/coin-ops.git
cd coin-ops
git checkout kazachuk
sudo bash scripts/vm1_setup.sh   # on VM1
sudo bash scripts/vm2_setup.sh   # on VM2
sudo bash scripts/vm3_setup.sh   # on VM3
sudo bash scripts/vm4_setup.sh   # on VM4
```

Each script installs OS packages, sets up a virtualenv (where applicable), copies the systemd unit file, and enables the service.

### Setup — Ansible

From the operator's workstation:

```bash
cd ansible
ansible-playbook playbooks/vm1.yml
ansible-playbook playbooks/vm2.yml
ansible-playbook playbooks/vm3.yml
ansible-playbook playbooks/vm4.yml
```

To pull fresh code on every VM after a `git push`:

```bash
ansible-playbook playbooks/update.yml
```

### Day-to-day operations (VM mode)

On each VM:
```bash
sudo systemctl status flask       # VM1
sudo systemctl status proxy       # VM2
sudo systemctl status consumer    # VM3
sudo systemctl status rabbitmq-server postgresql redis-server   # VM3/VM4
```

Logs:
```bash
sudo journalctl -u flask -n 50 -f
sudo journalctl -u proxy -n 50 -f
sudo journalctl -u consumer -n 50 -f
```

---

## Mode B — Docker deployment (single host)

The same application packaged into containers and orchestrated by Docker Compose. The whole stack runs on a single Linux host (a VM, a bare-metal server, or a cloud instance).

### Why Docker

| Aspect            | VM mode (4 VMs)         | Docker mode (1 host)            |
|-------------------|-------------------------|---------------------------------|
| Disk footprint    | ~12 GB (4 x 3 GB)       | ~600 MB of images               |
| Cold start time   | ~4 minutes              | ~15 seconds                     |
| Setup commands    | dozens (per VM)         | one (`docker compose up -d`)    |
| Reproducibility   | depends on VM state     | same image runs anywhere        |
| Resource overhead | one full OS per service | shared host kernel              |

### Container layout

The Docker stack consists of six containers on a single Compose-managed network (`coinops-net`):

| Container          | Image                              | Role                          |
|--------------------|------------------------------------|-------------------------------|
| coinops-frontend   | `coinops-frontend:latest` (custom) | Flask UI                      |
| coinops-proxy      | `coinops-proxy:latest` (custom)    | Go API proxy                  |
| coinops-consumer   | `coinops-consumer:latest` (custom) | Consumer + history API        |
| coinops-rabbitmq   | `rabbitmq:3-management-alpine`     | Message broker + management UI|
| coinops-postgres   | `postgres:16-alpine`               | Historical records storage    |
| coinops-redis      | `redis:7-alpine`                   | User preferences storage      |

Containers reach each other by service name (`rabbitmq`, `postgres`, `redis`, `proxy`, `consumer`, `frontend`) — there are no hardcoded IPs.

### Image sizing

All custom images use **multi-stage builds** to keep the runtime layer minimal. The Go proxy is built on `golang:1.23-alpine` and shipped on plain `alpine:3.20`. The Python services use `python:3.12-alpine` (frontend) and `python:3.12-slim` (consumer, where `psycopg2-binary` requires glibc).

| Image              | Disk usage | Content size |
|--------------------|------------|--------------|
| coinops-proxy      | 23.9 MB    | 6.86 MB      |
| coinops-frontend   | 109 MB     | 25.1 MB      |
| coinops-consumer   | 245 MB     | 53.1 MB      |
| **Sum (custom)**   | **~378 MB**| **~85 MB**   |

The Go proxy is a particularly clean example of multi-stage build: a single statically linked Go binary on a near-empty Alpine base produces a sub-7 MB image.

### Repository layout for Docker

```
docker/
├── Dockerfile.frontend     # multi-stage build for Flask UI
├── Dockerfile.proxy        # multi-stage build for Go proxy
├── Dockerfile.consumer     # multi-stage build for consumer
├── docker-compose.yml      # full stack definition
└── init.sql                # PostgreSQL schema bootstrap
```

`init.sql` is mounted into the postgres container's `docker-entrypoint-initdb.d/`, so the `rates` table and its indexes are created automatically on first start.

### Setup — Docker mode

Prerequisites on the host:
- Docker Engine 24+
- Docker Compose v2 (the `docker compose` plugin)

Steps:

```bash
# 1. Clone the repo on the deployment host
git clone https://github.com/ua-academy-projects/coin-ops.git
cd coin-ops
git checkout kazachuk

# 2. Build the three custom images
docker build -f docker/Dockerfile.proxy    -t coinops-proxy:latest    .
docker build -f docker/Dockerfile.frontend -t coinops-frontend:latest .
docker build -f docker/Dockerfile.consumer -t coinops-consumer:latest .

# 3. Start the full stack
cd docker
docker compose up -d
```

The compose file declares health checks for `postgres`, `redis`, and `rabbitmq`, and uses `depends_on: condition: service_healthy` so that `proxy`, `consumer`, and `frontend` only start once their dependencies are ready. This eliminates the boot-order race that exists in VM mode.

After the stack is up, the UI is reachable at `http://<host>:5000` and the RabbitMQ management UI at `http://<host>:15672` (user `coinops`, password `coinops123`).

### Day-to-day operations (Docker mode)

```bash
# Status of every container
docker compose ps

# Tail logs of one or all services
docker compose logs -f
docker compose logs -f frontend

# Restart one service
docker compose restart consumer

# Rebuild and redeploy a single service after a code change
docker build -f docker/Dockerfile.frontend -t coinops-frontend:latest .
docker compose up -d frontend

# Stop everything (containers removed, volumes preserved)
docker compose down

# Stop and wipe data (drops the postgres-data volume too)
docker compose down -v
```

PostgreSQL data lives in the named volume `postgres-data`, so it survives `docker compose down`. Use `down -v` only when you intentionally want a clean database.

### Environment variables

Each custom image reads its connection settings from environment variables, with defaults that match the VM layout (so the same binaries still work on VM1–VM4 without compose).

| Service   | Variable          | Default (VM mode)                                       | Set in compose to    |
|-----------|-------------------|---------------------------------------------------------|----------------------|
| proxy     | `RABBITMQ_URL`    | `amqp://coinops:coinops123@192.168.56.104:5672/`        | `rabbitmq:5672`      |
| proxy     | `PORT`            | `8080`                                                  | `8080`               |
| consumer  | `DB_HOST`         | `localhost`                                             | `postgres`           |
| consumer  | `RABBITMQ_HOST`   | `192.168.56.104`                                        | `rabbitmq`           |
| consumer  | `REDIS_HOST`      | `localhost`                                             | `redis`              |
| frontend  | `PROXY_URL`       | `http://192.168.56.102:8080`                            | `http://proxy:8080`  |
| frontend  | `CONSUMER_URL`    | `http://192.168.56.103:5001`                            | `http://consumer:5001` |

---

## Blockers encountered & workarounds

### 1. RabbitMQ `guest` user blocked from non-localhost
**Symptom:** `User can only log in via localhost` when opening the management UI from a browser on the host.
**Cause:** RabbitMQ refuses the default `guest` account from any non-loopback connection.
**Fix:** Created a dedicated `coinops` user with administrator tag and full permissions on `/`. In Docker mode this is handled automatically by setting `RABBITMQ_DEFAULT_USER` / `RABBITMQ_DEFAULT_PASS` on the official image.

### 2. Race condition between proxy and RabbitMQ at boot
**Symptom:** After a full host reboot, history stopped updating. Logs showed `RabbitMQ not connected` from the proxy.
**Cause:** VM2 (proxy) starts faster than VM4 (RabbitMQ). The proxy tries to dial RabbitMQ before it is ready and gives up.
**Fix in VM mode:** Added retry loops on both sides — Go proxy keeps retrying every 5 seconds, Python consumer wraps the consume loop in a try/except with a 5-second sleep. Startup order becomes irrelevant.
**Fix in Docker mode:** RabbitMQ has a `healthcheck` and proxy/consumer wait for `service_healthy` before starting. The race cannot happen at all.

### 3. Crypto rates were stored in UAH instead of USD
**Symptom:** History chart for BTC showed values around 2,900,000.
**Cause:** Initial CoinGecko API call used `vs_currencies=uah`. After switching to `vs_currencies=usd`, old UAH-denominated rows remained in the database and broke the chart scale.
**Fix:**
1. Changed the proxy to fetch USD: `vs_currencies=usd` and read `data["usd"]`
2. Cleaned up legacy rows:
   ```sql
   DELETE FROM rates
   WHERE currency IN ('BTC','ETH','SOL','BNB','ADA','XRP','DOGE','DOT','AVAX','LINK')
     AND created_at < '2026-04-06 00:00:00';
   ```
3. Updated the UI to label crypto values as USD and fiat as UAH consistently

### 4. Filter buttons on the history page didn't reflect the active period
**Symptom:** Clicking "Week" reloaded the page but the highlighted button was always "Day".
**Cause:** The `active` CSS class was hardcoded in the template. JavaScript tried to toggle it after a full page reload, which lost the state.
**Fix:** Pass `current_hours` from Flask to the template and render the `active` class with a Jinja conditional.

### 5. VM clock drift after host sleep/wake
**Symptom:** Records were saved with timestamps from a previous day.
**Cause:** VirtualBox does not always resync the guest clock after the host wakes from sleep.
**Fix:** On every VM:
```bash
sudo timedatectl set-timezone Europe/Kyiv
sudo timedatectl set-ntp on
```

### 6. `venv` disappeared after a `git reset`
**Symptom:** `source venv/bin/activate: No such file or directory` after pulling fresh code.
**Cause:** `venv/` was tracked in an early commit, then removed and added to `.gitignore`. A reset wiped it locally.
**Fix:** Recreate the venv when missing. In Docker mode the venv is built inside the image and never touched at runtime, so this class of problems disappears entirely.

### 7. `psycopg2-binary` on Alpine
**Symptom:** First attempt to use `python:3.12-alpine` for the consumer failed because `psycopg2-binary` ships glibc-linked wheels that do not run on Alpine's musl libc.
**Cause:** Alpine uses musl instead of glibc; precompiled Python wheels with native extensions often only target glibc.
**Fix:** Switched the consumer image to `python:3.12-slim` (Debian-based). The proxy and frontend still use Alpine because they have no native dependencies. The size penalty is ~50 MB, well worth the simplicity.

### 8. Stale containers blocking ports during Compose first run
**Symptom:** `Bind for 0.0.0.0:5001 failed: port is already allocated` on `docker compose up -d`.
**Cause:** A previous standalone test container (`frontend-test`) was still running on the same port.
**Fix:** `docker rm -f <name>` for the leftover container, then re-run compose. As a habit, always clean up ad-hoc test containers before bringing up the full stack.

---

## Repository layout

```
coin-ops/
├── frontend/                   # Flask UI (used by VM1 and Docker frontend)
│   ├── app.py
│   ├── requirements.txt
│   └── templates/
│       ├── index.html
│       └── history.html
├── proxy/                      # Go proxy (used by VM2 and Docker proxy)
│   ├── main.go
│   ├── go.mod
│   └── go.sum
├── consumer/                   # Consumer + history API (used by VM3 and Docker consumer)
│   ├── consumer.py
│   └── requirements.txt
├── docker/                     # Docker deployment
│   ├── Dockerfile.frontend
│   ├── Dockerfile.proxy
│   ├── Dockerfile.consumer
│   ├── docker-compose.yml
│   └── init.sql
├── scripts/                    # Bash setup scripts and systemd unit files (VM mode)
│   ├── vm1_setup.sh
│   ├── vm2_setup.sh
│   ├── vm3_setup.sh
│   ├── vm4_setup.sh
│   ├── flask.service
│   ├── proxy.service
│   ├── consumer.service
│   └── rabbitmq-server.service
├── ansible/                    # Ansible playbooks (VM mode)
│   ├── ansible.cfg
│   ├── inventory.ini
│   └── playbooks/
│       ├── vm1.yml
│       ├── vm2.yml
│       ├── vm3.yml
│       ├── vm4.yml
│       └── update.yml
└── README.md
```

---

## Out of scope for this iteration

As specified in the iteration brief: containers were originally deferred to a later iteration, but the Docker mode in this README is an early start on that work. Kubernetes, Helm, full automation/orchestration, public cloud deployment, and the team-integrated version are still out of scope.