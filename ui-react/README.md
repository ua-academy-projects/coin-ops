# coin-ops UI

React + Vite + TypeScript frontend for the Coin-Ops Polymarket dashboard.

## Prerequisites

- Node.js 22+
- Go proxy running on `:8080` (see `proxy/`)
- FastAPI history service running on `:8000` (see `history/`)

## Quick start

```bash
cd ui-react
npm install
npm run dev
```

Opens at `http://localhost:3000`. The dev server proxies API requests to the local backend services.

## Environment variables

By default the dev server proxies to `localhost`. Override with env vars:

| Variable | Default | Description |
|---|---|---|
| `PROXY_HOST` | `http://172.31.1.11:8080` | Go proxy host |
| `PROXY_PORT` | `8080` | Go proxy port |
| `HISTORY_HOST` | `http://172.31.1.11:8080` | FastAPI host |
| `HISTORY_PORT` | `8000` | FastAPI port |


## Commands

| Command | Description |
|---|---|
| `npm run dev` | Dev server on `:3000` with hot reload |
| `npm run lint` | TypeScript type check |
| `npm run preview` | Preview the production build locally |

## API contract

The UI talks to two services through Vite's dev proxy:

| Prefix | Service | Endpoints used |
|---|---|---|
| `/api` | Go proxy | `/current`, `/whales`, `/prices`, `/state`, `/health` |
| `/history-api` | FastAPI | `/history`, `/history/{slug}`, `/prices/history/{coin}`, `/health` |

Both `RUNTIME_BACKEND=external` and `RUNTIME_BACKEND=postgres` expose the same HTTP contract — the UI works against either mode without changes.
