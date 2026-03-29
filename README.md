# Monero Privacy Analytics System

Real-time and predictive privacy metrics for the Monero network. Estimates the *quality of anonymity* in a block context — Monero's privacy never breaks; this system tells you **when it's best to transact**.

```
Frontend (React) → Backend (FastAPI) → Monero Node RPC + CoinGecko
                                     ↓
                               PostgreSQL DB
```

---

## Architecture

| Component | VM | Technology |
|---|---|---|
| Dashboard UI | VM1 | React, Nginx |
| REST API | VM2 | FastAPI, Python 3.11 |
| Data Worker | VM2 | Asyncio background loop |
| Database | VM3 | PostgreSQL 16 |

All VMs run **Alpine Linux** with **OpenRC** as their init system.

---

## Quick Start (Local Dev)

```bash
git clone https://github.com/ua-academy-projects/coin-ops.git
cd coin-ops
docker compose up --build
```

- Frontend: http://localhost:3000
- API: http://localhost:8000
- API docs: http://localhost:8000/docs

> **Note:** By default, the worker tries to connect to `monerod:18081`. Without a real node, worker cycles will log errors but the API will still serve whatever data is in the DB. Point `MONERO_RPC_HOST` at a real monerod instance.

---

## Production Deployment

### Prerequisites

- 3 VMs (Alpine Linux)
- A running `monerod` instance accessible from VM2
- SSH access to all VMs

### Step 1 — Prepare secrets

On each VM, create `/etc/monero/deploy.env`:

```bash
sudo cp deploy/deploy.env.template /etc/monero/deploy.env
sudo vi /etc/monero/deploy.env  # fill in real values
```

On VM2 additionally:

```bash
sudo cp deploy/vm2/backend.env.template /etc/monero/backend.env
sudo vi /etc/monero/backend.env
```

### Step 2 — Copy scripts to VMs

```bash
# From your workstation:
scp deploy/vm1/* user@VM1_IP:/opt/monero-scripts/
scp deploy/vm2/* user@VM2_IP:/opt/monero-scripts/
scp deploy/vm3/* user@VM3_IP:/opt/monero-scripts/
scp database/schema.sql user@VM3_IP:/opt/monero-scripts/
```

### Step 3 — Bootstrap each VM

```bash
# VM3 first (database must be up before backend)
ssh user@VM3_IP "sudo bash /opt/monero-scripts/bootstrap.sh vm3"

# VM2 next
ssh user@VM2_IP "sudo bash /opt/monero-scripts/bootstrap.sh vm2"

# VM1 last
ssh user@VM1_IP "sudo bash /opt/monero-scripts/bootstrap.sh vm1"
```

### Step 4 — Verify

```bash
# VM1
curl http://VM1_IP/health

# VM2
curl http://VM2_IP:8000/health
curl http://VM2_IP:8000/stats

# VM3
psql -h VM3_IP -U monero -d monero_privacy -c "SELECT COUNT(*) FROM blocks;"
```

---

## Auto-Deployment

Each VM polls GitHub every **60 seconds** via a **crond** job (Alpine cron).

```
git fetch origin main
if local_commit != remote_commit:
    git pull
    restart services
```

To trigger a deploy: just push to `main`. Within 60 seconds all VMs will update automatically.

Check deploy logs:
```bash
tail -f /var/log/monero-deploy.log   # on any VM
```

---

## API Reference

| Endpoint | Description |
|---|---|
| `GET /health` | Service liveness |
| `GET /stats` | Full network snapshot |
| `GET /blocks/latest?limit=20` | Recent blocks |
| `GET /privacy/current` | Current block privacy score |
| `GET /privacy/history?limit=50` | Privacy score history |
| `GET /privacy/prediction` | Next block prediction |
| `GET /price` | Latest XMR/USD |
| `GET /price/history` | Price history |
| `GET /trend` | TX count trend (regression slope) |

Full interactive docs at `http://VM2_IP:8000/docs`

---

## Privacy Engine

### Current Block Score

```python
privacy_score = min(1.0, tx_count / 20)
```

More transactions in a block = larger anonymity set = better privacy quality.

### Next Block Prediction

1. **Capacity**: `max_tx = median_block_size / avg_tx_size`
2. **Expected TXs**: `expected_tx = min(mempool_size, max_tx)`
3. **Inclusion probability**: `p = min(1, your_fee / avg_mempool_fee)`
4. **Privacy score**: `score = (expected_tx / 25) × inclusion_probability`
5. **Risk classification**:
   - `score < 0.3` → 🛑 **LOW** — WAIT
   - `score < 0.7` → ⚠️ **MEDIUM** — OPTIONAL WAIT
   - `score ≥ 0.7` → ✅ **HIGH** — SEND

### Important

> Monero's cryptographic privacy (ring signatures, stealth addresses, RingCT) **never breaks**. This system estimates the *quality of the anonymity set* — i.e., how many other transactions your transaction hides among. A LOW score means fewer peers, not broken privacy.

---

## Worker Cycle (every 10s)

```
1. get_block_count         → latest height
2. get_block_header        → store in blocks table
3. get_transaction_pool    → mempool size, fees, tx sizes
4. Compute averages        → last 50 blocks
5. Store network_stats
6. Compute privacy_metrics (current block)
7. Compute next_block_prediction
8. Fetch XMR price         → every ~5 minutes (CoinGecko)
```

---

## Networking

```
VM1 (Frontend)  →  http://VM2_IP:8000  (API)
VM2 (Backend)   →  postgresql://VM3_IP:5432
VM2 (Worker)    →  http://monerod:18081/json_rpc
```

Firewall rules needed:
- VM1: inbound 80 (public), outbound 8000→VM2
- VM2: inbound 8000 (from VM1 + admin), outbound 5432→VM3, 18081→monerod
- VM3: inbound 5432 (from VM2 only)

---

## Monero RPC Methods Used

| Method | Purpose |
|---|---|
| `get_block_count` | Current blockchain height |
| `get_block_header_by_height` | Block metadata (txs, size, difficulty) |
| `get_last_block_header` | Latest block info |
| `get_transaction_pool` | Mempool contents and fees |
| `get_info` | General node info |

---

## License

MIT
