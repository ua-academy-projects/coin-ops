# MVP Increment Design — SSH, Common Role, Redis, Prices

**Date:** 2026-04-03
**Author:** Volodymyr Shabat + Claude
**Status:** Draft

---

## Context

The coin-ops project is a Polymarket Intelligence Dashboard — three services across three Hyper-V VMs, connected by RabbitMQ. The base implementation (commit `a1790bd`) is complete and working: proxy fetches markets + whale data, publishes to queue, consumer persists to PostgreSQL, UI displays live + history views.

This is the first incremental improvement. The goal is demonstrable DevOps progress for mentor/expert review — not complexity for its own sake. Each step builds on existing patterns and conventions.

**Who this is for:** A DevOps intern building a portfolio project. Employers and mentors should see clean infrastructure decisions, not just features.

---

## Step 1: SSH Key-Only Auth + Common Ansible Role

### 1.1 SSH Key-Only

**What:** Remove password-based SSH from Ansible. Use Vagrant-generated private keys via `-i` flag or `ansible_ssh_private_key_file` in host_vars.

**Why:** Password auth in automation is a bad practice. Keys are standard in any real environment.

**Current state (already partially done at HEAD):**
- `ansible_password: vagrant` removed from `group_vars/all/main.yml`
- `host_vars/*.yml` gitignored
- `host_vars/softserve-node-01.yml.example` committed as template

**Remaining work:**
- Create `.yml.example` files for node-02 and node-03 (same pattern as node-01)
- Verify the existing host_vars pattern works with `ansible all -m ping`
- Document the `-i` flag alternative in deployment.md

### 1.2 Common Ansible Role

**What:** New `ansible/roles/common/` role that runs on ALL three VMs before any service-specific role.

**Tasks:**
1. `apt update && apt upgrade` (with `cache_valid_time: 3600` to avoid hammering apt)
2. Set timezone to UTC (`timedatectl set-timezone UTC`)
3. Install essential packages: `curl`, `htop`, `jq`, `acl`, `unattended-upgrades`
4. Configure UFW firewall:
   - Default deny incoming, allow outgoing
   - Allow SSH (22) on all hosts
   - Allow service-specific ports passed via variable (see below)
5. Ensure NTP is running (`systemd-timesyncd`)

**Port variable pattern:**
```yaml
# In each host's role or group_vars, define:
# common_allowed_ports: [22, 8080]
#
# The common role iterates and opens them.
# Default: [22] (SSH only)
```

This avoids hardcoding port knowledge in the common role. Each service role sets its own ports.

**File structure (follows existing convention):**
```
ansible/roles/common/
├── tasks/main.yml
├── handlers/main.yml      # handler: restart ufw
└── defaults/main.yml      # common_allowed_ports: [22]
```

**Integration:** `provision.yml` calls `common` role on `all` hosts before service-specific roles. `deploy.yml` unchanged — it only deploys services, not infrastructure.

---

## Step 2: Redis on node-02 (View State)

### 2.1 Purpose

Redis stores UI view state — which tab is active, which market the user drilled into. No login system. A random UUID is generated in the browser, stored as a cookie, and used as the Redis key. State survives page refresh.

### 2.2 Architecture Placement

Redis lives on **node-02** (proxy host). Rationale:
- The proxy is already the UI's backend for all data (`/current`, `/whales`)
- Adding `/state` GET/POST to the proxy keeps the "single backend" pattern
- Redis on localhost avoids cross-VM latency for state reads
- node-01 already runs PostgreSQL + RabbitMQ; adding Redis there would overload it conceptually (persistence node vs. serving node)

### 2.3 Data Model

```
Redis key:   "session:<uuid>"
Redis value:  JSON string
TTL:         24 hours (auto-expire abandoned sessions)
```

State payload (what the browser sends/receives):
```json
{
  "active_tab": "live",
  "selected_market": "will-bitcoin-reach-100k",
  "scroll_y": 420
}
```

Intentionally minimal. No sensitive data. If Redis is down, the UI works normally — it just doesn't remember state on refresh. Graceful degradation.

### 2.4 Proxy Changes (proxy/main.go)

- Add `github.com/redis/go-redis/v9` dependency
- New field on `Server` struct: `rdb *redis.Client`
- Connect to Redis on startup (from `REDIS_URL` env var, default `localhost:6379`)
- Two new handlers:
  - `GET /state?sid=<uuid>` → Redis GET, return JSON (or `{}` if not found)
  - `POST /state?sid=<uuid>` → read body, Redis SET with 24h TTL
- Both wrapped in `corsMiddleware` (same as all other endpoints)
- If Redis is unreachable: `/state` returns 503, proxy continues serving other endpoints normally

### 2.5 Ansible Changes

**Provisioning (node-02):**
- Install `redis-server` package in proxy host group
- Ensure redis-server is enabled and started
- Redis binds to `127.0.0.1` only (default, no config change needed)

**Deployment:**
- `proxy.env.j2` gets new line: `REDIS_URL=redis://127.0.0.1:6379/0`
- `proxy.service.j2` gets: `After=network.target redis-server.service`
- Common role opens no new ports for Redis (localhost only)

### 2.6 UI Changes (minimal, for state to work)

- On page load: check for `coinops_sid` cookie. If absent, generate UUID, set cookie.
- On tab switch / market selection: `POST /state?sid=<uuid>` with current state
- On page load (after cookie check): `GET /state?sid=<uuid>`, restore tab/market if present
- If `/state` fails: silently ignore, default to Live tab. No error shown to user.

---

## Step 3: `/prices` Endpoint + Price History (CoinGecko + NBU)

### 3.1 Purpose

Show live crypto prices (BTC, ETH in USD) and USD/UAH exchange rate on the dashboard. **Also persist prices to PostgreSQL** so the UI can display price history charts — same pattern as market snapshots.

### 3.2 External APIs

**CoinGecko** (free, no auth):
```
GET https://api.coingecko.com/api/v3/simple/price?ids=bitcoin,ethereum&vs_currencies=usd&include_24hr_change=true
```
Returns: `{"bitcoin":{"usd":97000,"usd_24h_change":-1.2},"ethereum":{"usd":3400,"usd_24h_change":0.8}}`

**NBU** (free, no auth):
```
GET https://bank.gov.ua/NBUStatService/v1/statdirectory/exchange?valcode=USD&json
```
Returns: `[{"rate":41.25,...}]`

### 3.3 Data Flow (follows existing architecture)

```
Proxy goroutine (every 60s)
  → fetch CoinGecko + NBU
  → update RAM cache (for /prices endpoint, instant response)
  → publish price messages to market_events queue
       ↓
Consumer (existing, on node-01)
  → detects message type "price"
  → INSERT INTO price_snapshots
       ↓
History API (existing, on node-01)
  → GET /prices/history/{coin} → time-series from PostgreSQL
       ↓
UI → Chart.js line graph (same pattern as market YES/NO chart)
```

### 3.4 Message Contract

Prices use the **same `market_events` queue** with an added `type` field. The consumer routes by type.

```json
{
  "type": "price",
  "coin": "bitcoin",
  "price_usd": 97000.00,
  "change_24h": -1.2,
  "fetched_at": "2026-04-03T12:00:00Z"
}
```

USD/UAH published as its own message:
```json
{
  "type": "price",
  "coin": "usd_uah",
  "price_usd": 41.25,
  "change_24h": 0.0,
  "fetched_at": "2026-04-03T12:00:00Z"
}
```

Backwards compatible: existing market messages have no `type` field, consumer treats them as before.

### 3.5 Schema Addition (history/schema.sql)

```sql
CREATE TABLE IF NOT EXISTS price_snapshots (
    id          SERIAL PRIMARY KEY,
    fetched_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    coin        TEXT NOT NULL,          -- "bitcoin", "ethereum", "usd_uah"
    price_usd   NUMERIC(16,2) NOT NULL,
    change_24h  NUMERIC(8,2),
    CONSTRAINT uq_price_coin_fetched UNIQUE (coin, fetched_at)
);

CREATE INDEX IF NOT EXISTS idx_price_snapshots_coin
    ON price_snapshots(coin, fetched_at DESC);
```

Same patterns as `market_snapshots`: TIMESTAMPTZ, unique constraint for idempotent writes, descending index for history queries.

### 3.6 Consumer Changes (history/consumer.py)

The callback checks for `type` field:
- If `type == "price"`: INSERT INTO `price_snapshots` with ON CONFLICT DO NOTHING
- If no `type` field (or `type == "market"`): existing INSERT INTO `market_snapshots` (unchanged)

Same ack-after-commit pattern. Same error handling (rollback + nack + requeue).

### 3.7 History API Changes (history/main.py)

New endpoint:
- `GET /prices/history/{coin}?limit=500` — returns time-series for a coin (bitcoin, ethereum, usd_uah)
  - Returns: `[{"fetched_at": "...", "price_usd": 97000, "change_24h": -1.2}, ...]`
  - Same pattern as existing `GET /history/{slug}`

### 3.8 Proxy Implementation (proxy/main.go)

**New types:**
```go
type Prices struct {
    BtcUsd         float64   `json:"btc_usd"`
    EthUsd         float64   `json:"eth_usd"`
    Btc24hChange   float64   `json:"btc_24h_change"`
    Eth24hChange   float64   `json:"eth_24h_change"`
    UsdUah         float64   `json:"usd_uah"`
    FetchedAt      time.Time `json:"fetched_at"`
}
```

**Cache + publish pattern:**
- New field on `Server.cache`: `prices Prices`
- Background goroutine: fetch CoinGecko + NBU every 60 seconds
- `fetchAndUpdatePrices()` runs once on startup, then via `time.Ticker`
- On each fetch: update RAM cache AND publish 3 messages to `market_events` queue (BTC, ETH, USD/UAH)
- Both API calls in sequence (only 2 calls)

**New endpoint:**
- `GET /prices` → returns cached Prices JSON (instant, from RAM)
- Wrapped in `corsMiddleware`

### 3.9 UI Changes (light tweaks, not a redesign)

**Ticker strip:**
- New constant: `PRICES_REFRESH_MS = 60_000`
- Fetch `PROXY_URL + '/prices'` on a separate interval (60s, not 30s like markets)
- Display in header: BTC $97,000 (+1.2%), ETH $3,400 (-0.8%), USD/UAH 41.25
- Green for positive 24h change, red for negative (matches YES/NO color convention)

**Price history chart:**
- Add a way to view price history (e.g., clickable coins in ticker → chart appears in History tab)
- Fetch `HISTORY_URL + '/prices/history/bitcoin?limit=500'`
- Chart.js line graph — same pattern as existing market YES/NO chart
- Shows price over time for selected coin

**State persistence:**
- Cookie-based session ID (from Step 2)
- Save/restore active tab and selected market/coin on page load

---

## Step 4: UI Improvements (future — NOT in this increment)

Noted for planning but not designed here:
- Full visual overhaul (modern crypto dashboard aesthetic)
- Better whale tracker presentation
- Category filters, sentiment indicators, volume heatmaps

---

## Step 5: Infrastructure & Implementation Guide

### 5.1 Purpose

A learning-oriented document for DevOps interns/trainees explaining *why* every infrastructure decision was made, *how* the pieces connect, and *what to watch for* operationally.

### 5.2 Deliverables

**`docs/architecture.md` updates:**
- Add Redis to the architecture diagram (on node-02)
- Add `/prices` and `/state` to proxy endpoint list
- Add CoinGecko and NBU to External APIs table
- Add Redis to the data flow description
- Update the infrastructure diagram to show Redis on node-02

**New `docs/infrastructure-guide.md`:**

Educational deep-dive covering:

1. **System overview** — what each VM runs and why it's there
2. **Network topology** — IPs, ports, which service talks to which, firewall rules
3. **Ansible explained** — inventory, group_vars, host_vars, roles structure, provision vs deploy, idempotency, handlers, templates. Walk through what each playbook does task by task.
4. **Systemd explained** — unit file anatomy, why Restart=on-failure not always, EnvironmentFile pattern, journalctl usage
5. **Message queue fundamentals** — why RabbitMQ, what durable/persistent means, prefetch_count, ack-after-commit pattern, what happens on crash
6. **Database decisions** — TIMESTAMPTZ, ON CONFLICT DO NOTHING, index design, why the consumer owns the schema
7. **Caching strategy** — Go RAM cache for whales/prices (when it's appropriate), Redis for session state (when you need persistence beyond process lifetime), why not Redis for everything
8. **Security basics** — UFW, NoNewPrivileges, PrivateTmp, SSH keys over passwords, secrets.yml gitignored, EnvironmentFile for secrets injection
9. **Failure modes** — what happens when RabbitMQ goes down, when PostgreSQL is full, when external APIs are unreachable, when Redis crashes
10. **Operational runbook** — how to check if things are working, how to restart, how to read logs, how to redeploy

Add to `DASHBOARD_PROJECT.md` deliverables list.

---

## Files Modified/Created

| File | Action | Step |
|------|--------|------|
| `ansible/host_vars/softserve-node-02.yml.example` | Create | 1 |
| `ansible/host_vars/softserve-node-03.yml.example` | Create | 1 |
| `ansible/roles/common/tasks/main.yml` | Create | 1 |
| `ansible/roles/common/handlers/main.yml` | Create | 1 |
| `ansible/roles/common/defaults/main.yml` | Create | 1 |
| `ansible/provision.yml` | Modify — add common role for all hosts, add redis-server for proxy host | 1+2 |
| `proxy/main.go` | Modify — add Redis client, `/state` endpoints, `/prices` endpoint, prices cache + publish | 2+3 |
| `proxy/go.mod` | Modify — add go-redis dependency | 2 |
| `ansible/roles/proxy/templates/proxy.env.j2` | Modify — add REDIS_URL | 2 |
| `ansible/roles/proxy/templates/proxy.service.j2` | Modify — add After=redis-server.service | 2 |
| `history/schema.sql` | Modify — add `price_snapshots` table + index | 3 |
| `history/consumer.py` | Modify — route by message type, add price INSERT | 3 |
| `history/main.py` | Modify — add `GET /prices/history/{coin}` endpoint | 3 |
| `ui/index.html` | Modify — add state save/restore, prices ticker, price history chart | 2+3 |
| `docs/architecture.md` | Modify — add Redis, /prices, /state, CoinGecko, NBU, price_snapshots | 5 |
| `docs/infrastructure-guide.md` | Create — full educational guide | 5 |
| `docs/deployment.md` | Modify — add Redis info, SSH key instructions | 5 |

---

## What This Does NOT Include

- Terraform (explicitly deferred)
- Docker/Kubernetes (out of scope per ТЗ)
- UI redesign (future increment)
- Whale data in queue/DB (whales stay cached in proxy RAM)
- CI/CD pipeline (future)
- SOL or other coins beyond BTC/ETH
- Login/authentication system

---

## Verification

After implementation, verify:

1. `ansible all -m ping` works with SSH keys only (no password prompt)
2. `ansible-playbook provision.yml` runs common role on all 3 hosts, installs Redis on node-02
3. `ansible-playbook deploy.yml` deploys updated proxy with Redis + prices support
4. `curl http://172.31.1.11:8080/prices` returns BTC, ETH, UAH data
5. `curl -X POST http://172.31.1.11:8080/state?sid=test123 -d '{"active_tab":"history"}'` → 200
6. `curl http://172.31.1.11:8080/state?sid=test123` → returns the saved state
7. `redis-cli -h 172.31.1.11 KEYS "session:*"` shows stored sessions
8. Wait 2-3 minutes, then: `curl http://172.31.1.10:8000/prices/history/bitcoin` returns stored price points
9. Open UI → prices ticker shows BTC/ETH/UAH in header
10. Click a coin in ticker → History tab shows price chart over time
11. Switch tabs → refresh page → state is restored
12. UFW is active on all VMs: `sudo ufw status` shows only expected ports
13. `docs/architecture.md` reflects Redis + new endpoints + price_snapshots
14. `docs/infrastructure-guide.md` exists and covers all sections
