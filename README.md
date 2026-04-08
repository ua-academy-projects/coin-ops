# CoinOps — Currency & Crypto Rates Monitoring System

A microservices application that fetches currency exchange rates from public APIs, stores historical data asynchronously via a message queue, and displays current and historical rates through a web UI.

Built as a DevOps internship iteration project, focused on multi-VM deployment, inter-service communication, and infrastructure automation.

---

## Architecture

```
                    ┌──────────────┐
                    │     User     │
                    └──────┬───────┘
                           │
                           ▼
              ┌────────────────────────┐
              │   VM1 — Web UI (Flask) │
              │   192.168.56.101:5000  │
              └─────┬──────────────┬───┘
                    │              │
        current data│              │history
                    ▼              ▼
        ┌───────────────────┐  ┌──────────────────────┐
        │ VM2 — Go Proxy    │  │ VM3 — History Service│
        │ 192.168.56.102    │  │ 192.168.56.103:5001  │
        │ :8080             │  │ + PostgreSQL         │
        └────┬────────┬─────┘  │ + Redis              │
             │        │        └────────▲─────────────┘
             │        │ publish          │ consume
             │        ▼                  │
             │   ┌──────────────────────┴─┐
             │   │ VM4 — RabbitMQ         │
             │   │ 192.168.56.104:5672    │
             │   └────────────────────────┘
             │
             ▼
       ┌──────────┐
       │ NBU API  │
       │ CoinGecko│
       └──────────┘
```

### Data flow

1. User opens the UI in a browser → Flask (VM1) renders the page
2. Flask requests current rates from the Go Proxy (VM2)
3. Proxy fetches data from NBU API (fiat) and CoinGecko (crypto)
4. Proxy returns the response to Flask AND publishes a normalized message to RabbitMQ (VM4)
5. The Consumer service on VM3 reads messages from RabbitMQ and stores them in PostgreSQL
6. When the user opens the History page, Flask requests historical records from the Consumer's HTTP API
7. User favorites (selected currencies) are stored in Redis on VM3 for cross-session persistence

---

## VM layout

| VM  | IP              | Role                          | Services                           |
|-----|-----------------|-------------------------------|------------------------------------|
| VM1 | 192.168.56.101  | Web UI                        | Flask (`flask.service`)            |
| VM2 | 192.168.56.102  | API Proxy                     | Go proxy (`proxy.service`)         |
| VM3 | 192.168.56.103  | History service + storage     | Consumer, PostgreSQL, Redis        |
| VM4 | 192.168.56.104  | Message broker                | RabbitMQ + management plugin       |

All VMs run **Ubuntu 24.04 Server** (no GUI), networked via VirtualBox host-only network.

---

## Tech stack

- **UI:** Python 3 + Flask + Jinja2 + vanilla JavaScript + Chart.js
- **Proxy:** Go (standard library + amqp091-go for RabbitMQ)
- **Consumer / History API:** Python 3 + Flask + pika + psycopg2 + redis-py
- **Storage:** PostgreSQL 16 (historical records), Redis 7 (user preferences)
- **Message broker:** RabbitMQ 3 with management plugin
- **Process management:** systemd unit files
- **Infrastructure automation:** Bash setup scripts + Ansible playbooks
- **Public APIs:** [bank.gov.ua](https://bank.gov.ua/NBUStatService/v1/statdirectory/exchange?json) (NBU), [coingecko.com](https://www.coingecko.com/en/api) (crypto)

---

## Service responsibilities

### VM1 — Flask UI (`frontend/app.py`)
- Serves the main page (`/`) with current rates and the history page (`/history`)
- Calls the Go proxy on VM2 to fetch live data
- Calls the Consumer on VM3 to fetch historical data and user favorites
- Forwards favorite-saving requests from the browser to the Consumer (`/api/favorites`)

### VM2 — Go Proxy (`proxy/main.go`)
- Exposes `/rates` (NBU fiat) and `/crypto` (CoinGecko) HTTP endpoints
- Fetches data from the upstream APIs on demand
- Publishes normalized rate events to the `rates` queue in RabbitMQ on every fetch
- Has a background `autoRefresh` goroutine that publishes fresh rates every 5 minutes regardless of user activity
- Implements connection retry logic — keeps reconnecting if RabbitMQ is unavailable at startup

### VM3 — Consumer + History API (`consumer/consumer.py`)
- Consumer thread listens on the `rates` queue and inserts records into the `rates` table in PostgreSQL
- Flask HTTP API exposes:
  - `GET /history?hours=N` — historical records for the last N hours
  - `GET /favorites` — list of user-favorited currency codes (from Redis)
  - `POST /favorites` — replaces the favorites set in Redis
- Has retry logic for the RabbitMQ connection (5-second backoff)

### VM4 — RabbitMQ
- Single durable queue `rates`
- Custom user `coinops` (no `guest` access from non-localhost)
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
- Compact currency converter (UAH for fiat, USD for crypto)
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

## Setup

### Prerequisites on the host machine
- VirtualBox 7+
- 4 Ubuntu 24.04 Server VMs on host-only network `192.168.56.0/24`
- SSH access to all VMs from the operator's workstation
- Ansible installed on the operator's workstation (only for the Ansible flow)

### Option A — Bash scripts (manual, per-VM)

On each VM, clone the repo and run the matching script:

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

### Option B — Ansible (recommended)

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

---

## Day-to-day operations

### Service status

On each VM:
```bash
sudo systemctl status flask       # VM1
sudo systemctl status proxy       # VM2
sudo systemctl status consumer    # VM3
sudo systemctl status rabbitmq-server postgresql redis-server   # VM3/VM4
```

### Logs

```bash
sudo journalctl -u flask -n 50 -f
sudo journalctl -u proxy -n 50 -f
sudo journalctl -u consumer -n 50 -f
```

### RabbitMQ management UI

```
http://192.168.56.104:15672
user: coinops
pass: coinops123
```

### PostgreSQL access

On VM3:
```bash
sudo -u postgres psql -d coinops
```

Useful queries:
```sql
SELECT COUNT(*) FROM rates;
SELECT currency, COUNT(*) FROM rates GROUP BY currency ORDER BY COUNT(*) DESC;
SELECT * FROM rates ORDER BY created_at DESC LIMIT 20;
```

---

## Blockers encountered & workarounds

### 1. RabbitMQ `guest` user blocked from non-localhost
**Symptom:** `User can only log in via localhost` when opening the management UI from a browser on the host.
**Cause:** RabbitMQ refuses the default `guest` account from any non-loopback connection.
**Fix:** Created a dedicated `coinops` user with administrator tag and full permissions on `/`:
```bash
sudo rabbitmqctl add_user coinops coinops123
sudo rabbitmqctl set_user_tags coinops administrator
sudo rabbitmqctl set_permissions -p / coinops ".*" ".*" ".*"
```

### 2. Race condition between proxy and RabbitMQ at boot
**Symptom:** After a full host reboot, history stopped updating. Logs showed `RabbitMQ not connected` from the proxy.
**Cause:** VM2 (proxy) starts faster than VM4 (RabbitMQ). The proxy tries to dial RabbitMQ before it is ready and gives up.
**Fix:** Added retry loops on both sides:
- Go proxy: `connectRabbitMQ()` keeps retrying every 5 seconds until success
- Python consumer: wraps the consume loop in `try/except` with a 5-second sleep on failure
This makes startup order irrelevant.

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
**Fix:** Recreate the venv when missing:
```bash
cd ~/coin-ops/<service>
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

---

## Repository layout

```
coin-ops/
├── frontend/                   # VM1 — Flask UI
│   ├── app.py
│   ├── requirements.txt
│   └── templates/
│       ├── index.html
│       └── history.html
├── proxy/                      # VM2 — Go proxy
│   ├── main.go
│   ├── go.mod
│   └── go.sum
├── consumer/                   # VM3 — Consumer + History API
│   └── consumer.py
├── scripts/                    # Bash setup scripts and systemd unit files
│   ├── vm1_setup.sh
│   ├── vm2_setup.sh
│   ├── vm3_setup.sh
│   ├── vm4_setup.sh
│   ├── flask.service
│   ├── proxy.service
│   ├── consumer.service
│   └── rabbitmq-server.service
├── ansible/                    # Ansible playbooks
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

As specified in the iteration brief: containers, Kubernetes, Helm, full automation/orchestration, and team-integrated versions are deferred to later iterations.
