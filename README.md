# coin-ops

UAH exchange rate tracker using the [National Bank of Ukraine open API](https://bank.gov.ua/ua/open-data/api-dev).

## Architecture (V1)

```
Browser → React UI → API Proxy (Python) → NBU API
```

| Component | Technology | Default port |
|---|---|---|
| UI | React + Vite | 5173 |
| API Proxy | Python / FastAPI | 8000 |

## Getting started

### Prerequisites

- Python 3.11+
- Node.js 20.16+

### API Proxy

```bash
cd api-proxy
python3 -m venv .venv
source .venv/bin/activate   # Windows: .venv\Scripts\activate
pip install -r requirements.txt
uvicorn main:app --port 8000
```

Endpoints:

| Method | Path | Description |
|---|---|---|
| `GET` | `/rates` | All current NBU exchange rates |
| `GET` | `/rates?cc=USD` | Filtered by currency code |
| `GET` | `/health` | Health check |

### UI

```bash
cd ui
npm install
npm run dev
```

Open [http://localhost:5173](http://localhost:5173).

For VM or production deployment, set the proxy URL before building:

```bash
VITE_API_PROXY_URL=http://<proxy-vm-ip>:8000 npm run build
# serve the dist/ folder with nginx or any static file server
```

## Configuration

Each service has its own `.env.example` — copy it on the respective VM:

```bash
# on the API Proxy VM
cp api-proxy/.env.example api-proxy/.env

# on the UI VM
cp ui/.env.example ui/.env
```

**api-proxy/.env**

| Variable | Default | Description |
|---|---|---|
| `PORT` | `8000` | Listen port |
| `CORS_ORIGINS` | `http://<ui-vm-ip>:5173` | Allowed origins (UI VM address) |

**ui/.env** *(build-time — used by `npm run build`)*

| Variable | Default | Description |
|---|---|---|
| `VITE_API_PROXY_URL` | `http://<proxy-vm-ip>:8000` | API Proxy address |

## Data source

**National Bank of Ukraine** — `https://bank.gov.ua/NBUStatService/v1/statdirectory/exchange?json`

No API key required. Rates are published each business day; the `exchangedate` field reflects the business date the rate applies to.

## What's next (V2+)

- RabbitMQ message queue
- History service (Go) consuming queue events
- PostgreSQL persistence
- Historical rates view in the UI
- VM-based isolated deployment
