# Smoke Suite

A small end-to-end confidence check for the coin-ops stack. It boots every
service on Docker Compose, waits for them to become healthy, and verifies the
most important application flows with a handful of HTTP calls.

It is **not** a full test pyramid. It does not replace the Go / Python / UI
unit test suites, and it does not cover every endpoint or UI interaction. It
exists so that after a change you can run one command and get a single yes/no
signal that the stack still boots and talks to itself.

## When to run it

Run the smoke suite:

- before opening a PR that touches more than one service, a Dockerfile, the
  queue contract, or the nginx gateway config;
- after rebasing a long-lived feature branch onto `dev`;
- after adjusting `docker-compose.smoke.yaml` or any of the smoke env files;
- on demand when you want a local end-to-end sanity check.

Do **not** wire it into every PR run. It starts a full stack (PostgreSQL,
RabbitMQ, Redis, proxy, history API, history consumer, nginx gateway), which
is slower and more fragile than the per-service unit checks already in
`.github/workflows/pr-checks.yml`. The repo policy is:

| Layer                         | Gate        | Where it runs                   |
| ----------------------------- | ----------- | ------------------------------- |
| Go / Python / UI unit + build | PR-blocking | `.github/workflows/pr-checks.yml` |
| Docker image builds           | PR-blocking | same workflow                   |
| **Smoke suite**               | Manual      | developer laptop / opt-in CI job |
| Full VM deploy (Ansible)      | Manual      | mentor / reviewer on the lab VMs |

## What it checks

The flows the team agreed to cover are deliberately narrow:

1. **Stack startup** — `docker compose up -d --wait` returns when every service
   that declares a `healthcheck:` is healthy (PostgreSQL, RabbitMQ, Redis,
   history-api, gateway). The Go `proxy` runs from a `scratch` image with no
   shell/`wget`/`nc` available for a container-level probe, and
   `history-consumer` is a queue worker with no HTTP surface — both are gated
   only by `service_started`, so a raw `curl` through the gateway can briefly
   race the proxy's bind on `:8080` and get a 502. The `./smoke.sh up` wrapper
   closes that window by polling the gateway's `/health`, `/api/health`, and
   `/history-api/health` until they return 200 before it hands control back.
   Prefer `./smoke.sh up` / `./smoke.sh check` over raw `docker compose up` for
   any manual poking.
2. **Proxy `/health`** — returns 200 and a JSON body with a `status` field,
   reached through the gateway at `/api/health`.
3. **History API `/health`** — same, through the gateway at
   `/history-api/health`.
4. **Gateway `/health`** — the nginx gateway itself answers 200.
5. **UI → backend path** — `GET /api/prices` through the gateway returns 200
   with a JSON body that contains the `btc_usd` key. This is the same routing
   layer the browser uses; it proves nginx → proxy → in-memory cache works.
6. **History read path** — `GET /history-api/history?limit=1` through the
   gateway returns 200 and a JSON array (empty is acceptable; the check is
   that the API can reach PostgreSQL and execute the query).

The suite also has a PostgreSQL-runtime mode:

```bash
./smoke/smoke.sh postgres-runtime
```

That mode boots a second Compose stack on `http://localhost:18081` with
`RUNTIME_BACKEND=postgres`, a pgmq/pg_cron-capable PostgreSQL image, and no
RabbitMQ or Redis services. In addition to health checks, it verifies:

1. `pgmq` and `pg_cron` are installed.
2. `/api/state` writes and reads through PostgreSQL session wrappers.
3. A direct `runtime.enqueue_event(...)` call is consumed by
   `history-consumer` and becomes readable through the history API.

### Deliberately out of scope

- **Full Ansible / three-VM deployment.** PostgreSQL-runtime mode checks the
  same runtime contract locally, but it does not replace a VM-level Ansible
  deployment when deployment templates or inventory behavior change.
- **Full UI rendering and end-to-end user journeys.** The smoke gateway
  serves a tiny placeholder page at `/`, not the built React bundle. Browser
  flows belong in a future dedicated UI/E2E layer, not here.
- **Upstream data providers.** The proxy calls Polymarket, CoinGecko, and
  the NBU. If those are unreachable the cache may be empty, but `/api/prices`
  still returns 200 with zero values — the smoke only asserts shape, not
  data.

## How to run it

Prerequisites:

- Docker with the Compose v2 plugin (`docker compose version` works).
- `curl` on `PATH`.
- The repo checked out; no `.env` or source loading needed — the smoke stack
  is self-contained under `smoke/env/`.

From the repo root:

```bash
./smoke/smoke.sh             # up → wait → check → down (default)
./smoke/smoke.sh --keep      # same, but leave the stack running on pass
./smoke/smoke.sh up          # just start the stack
./smoke/smoke.sh check       # run checks against an already-running stack
./smoke/smoke.sh logs        # tail logs (add a service name for just one)
./smoke/smoke.sh down        # stop and remove the stack

./smoke/smoke.sh postgres-runtime          # postgres mode: up → check → down
./smoke/smoke.sh postgres-runtime --keep   # leave postgres-mode stack running
./smoke/smoke.sh postgres-runtime up
./smoke/smoke.sh postgres-runtime check
./smoke/smoke.sh postgres-runtime down
```

On success the script exits 0 and prints a summary:

```
── summary ──
  PASS  Stack services are healthy
  PASS  Proxy /health responds 200
  PASS  History API /health responds 200
  PASS  Gateway /health responds 200
  PASS  UI → backend: GET /api/prices returns JSON
  PASS  History read-path: GET /history-api/history returns JSON array
✔ 6/6 checks passed
```

On failure the stack is left running so you can inspect it:

```bash
./smoke/smoke.sh logs history-api     # per-service logs
./smoke/smoke.sh logs                 # all logs
./smoke/smoke.sh down                 # tear down when done debugging
```

### Ports

The external-mode stack exposes **only** the gateway on the host at
`http://localhost:18080`. The postgres-runtime stack uses
`http://localhost:18081` so both modes can be inspected independently. Proxy,
history API, PostgreSQL, RabbitMQ, and Redis are reachable only on the internal
compose network. Override with `SMOKE_GATEWAY_URL=... ./smoke/smoke.sh` if the
default port is taken.

### Timeouts

`SMOKE_WAIT_TIMEOUT` (default `180` seconds) is the deadline for both
`docker compose up --wait` and the subsequent gateway-route readiness probe.
Override with `SMOKE_WAIT_TIMEOUT=300 ./smoke/smoke.sh` on slower machines or
first runs where images still need to build.

## Files

```
smoke/
├── docker-compose.smoke.yaml   # single-host stack
├── docker-compose.postgres-runtime.yaml
├── postgres-runtime-bootstrap.sh
├── nginx.smoke.conf            # gateway routes for smoke
├── env/
│   ├── postgres.env            # throwaway credentials (smoketest only)
│   ├── rabbitmq.env
│   ├── proxy.env
│   ├── proxy.postgres.env
│   ├── history.postgres.env
│   └── history.env
└── smoke.sh                    # orchestrator + checks
```

The env files contain throwaway credentials used only by the smoke stack on
the local machine. They are safe to commit and must not be reused anywhere
else.

## Extending the suite

Keep it small. The point of this suite is "does the stack boot and talk to
itself," not "does every endpoint behave correctly." Before adding a check,
ask:

- Does it cover a **flow** (service-to-service path) or just one handler?
- Will it stay green when upstream providers (CoinGecko, Polymarket, NBU)
  are slow or unreachable?
- Is it fast enough to run in under a minute against an already-up stack?

If the answer to any of these is no, the check belongs in the per-service
unit tests, in a future UI/E2E layer, or in a manual VM run — not here.

To add a check:

1. Write a bash function in `smoke/smoke.sh` that exits 0 on pass, non-zero
   on fail, and prints a short `info` line with enough detail for a failed
   run.
2. Add a `"check_your_thing|Human-readable label"` entry to the `CHECKS`
   array.
3. If it depends on new state, consider whether the stack needs new env
   configuration or a longer `SMOKE_WAIT_TIMEOUT`.
