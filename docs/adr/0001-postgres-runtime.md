# ADR 0001: Postgres-native runtime layer - **Status**: Accepted
- **Date**: 2026-04-21
- **Deciders**: Team consensus
- **Context reference**: Issue #8
## 1. Context
The system currently runs two auxiliary services next to Postgres, plus an in-process cache inside the Go proxy:

| Component | Role | Pain |
|---|---|---|
| RabbitMQ (node-01) | Transport for market/price events | Extra VM + second persistence store; DLQ only inspectable via Rabbit UI |
| Redis (node-02) | Proxy session KV (`session:{sid}`, 24 h) | Another VM; non-durable by default; inconsistent with Postgres on crash |
| Proxy in-process cache (node-02) | Whales (5 min), BTC/ETH/UAH prices (60 s), current markets — held in `s.cache` guarded by a `sync.RWMutex` (`proxy/main.go:371-404,453-456`) | Disappears on every proxy restart; not visible to operators; split responsibility with Redis confuses readers; no shared view if the proxy ever scales horizontally |

Mentor direction: Redis **and** RabbitMQ should be replaced by **PostgreSQL mechanisms** — specifically `pgmq`, `pg_cron`, `LISTEN/NOTIFY`, advisory locks, and `UNLOGGED` + `JSONB`. A plain polling table is explicitly out of scope.

Postgres is already our system of record. Moving transport and cache inside it collapses three services into one, makes every runtime artefact queryable with SQL, and removes a full class of "two datastores drifted" failures.

---

## 2. Decisions
### Shared Infrastructure
- **Base image**: custom, built from `quay.io/tembo/pg16-pgmq` + `pg_cron`. Tembo's `pg16-pgmq` ships `pgmq` cleanly, but no public Tembo image pairs `pgmq` and `pg_cron` in one layer. We ship a small Dockerfile that adds `postgresql-16-cron` on top and sets `shared_preload_libraries = 'pg_cron,pgmq'`. Alternative considered (`FROM postgres:16` + both extensions via apt) is equivalent effort and loses Tembo's `pgmq` patch level, so we start from the Tembo base.
- **Scheduler**: adopt `pg_cron`.
### Queue Schema & Functions
- **Queue engine**: `pgmq`. No custom queue table.
- **Delivery semantics**: at-least-once transport (`pgmq` visibility timeout + explicit ack) + idempotent writes (`ON CONFLICT DO NOTHING`) → effectively exactly-once persistence. No exactly-once transport.
- **Coordination**: single active consumer via `pg_try_advisory_lock` in namespace `0x52554E54` ("RUNT"), key `1` = `single-consumer-events`.
- **Wake-up**: `LISTEN runtime_events` + `pg_notify` from an AFTER-INSERT trigger on the `pgmq` queue table. No hot-polling.
- **Retries**: SQL-side exponential backoff `min(120, 5 * 2^attempt)` s, capped at 3 attempts, then `events_dlq` + `runtime.dead_letter_audit`.
- **Scheduler job**: `runtime.dlq_reap` nightly via `pg_cron`.
### Cache & Session
- **Cache & session engine**: `UNLOGGED` table + `JSONB` + `expires_at`.
- **Storage semantics**: `UNLOGGED` skips WAL for cache rows — on crash the cache is truncated, which is the correct semantics (same as Redis without AOF). Sessions live in a separate table and may be `LOGGED` once we decide they need to survive restart; the first cut keeps both `UNLOGGED` for throughput.
- **Scheduler job**: `runtime.cache_reap` every minute via `pg_cron`.

---

## 3. Queue API

All functions in schema `runtime`, `SECURITY DEFINER`. Signatures match `runtime/02_wrappers.sql` and `runtime/05_dlq.sql`, merged on `dev` via PR #23 (together with `00_run_all.sql`, `01_schema.sql`, `03_notify.sql`, `04_advisory.sql`, and `runtime/tests/test_runtime.sql`). No caller on `dev` invokes these functions yet; the proxy/consumer switch is the separate rollout described in §4–§5.

```sql
-- Publish
runtime.enqueue_event(p_payload JSONB)                       RETURNS BIGINT

-- Consume
runtime.claim_events(p_n INT DEFAULT 1, p_vt INT DEFAULT 30) RETURNS SETOF pgmq.message_record
runtime.ack_event   (p_msg_id BIGINT)                        RETURNS VOID
runtime.fail_event  (p_msg_id    BIGINT,
                     p_error     TEXT DEFAULT NULL,
                     p_max_tries INT  DEFAULT 3)             RETURNS VOID

-- DLQ ops
runtime.dlq_pending     (p_limit INT DEFAULT 50,
                         p_vt    INT DEFAULT 0)              RETURNS SETOF pgmq.message_record
runtime.dlq_replay      (p_dlq_msg_id BIGINT)                RETURNS BIGINT
runtime.dlq_discard     (p_dlq_msg_id BIGINT)                RETURNS VOID
runtime.dlq_replay_all  ()                                   RETURNS INT
runtime.dlq_reap_expired(p_older_than INTERVAL DEFAULT '30 days') RETURNS INT

-- Coordination
runtime.advisory_try_lock(p_key INT)                         RETURNS BOOLEAN
runtime.advisory_lock    (p_key INT)                         RETURNS VOID
runtime.advisory_unlock  (p_key INT)                         RETURNS BOOLEAN

-- Observability
SELECT * FROM runtime.queue_depth;     -- depth per queue
SELECT * FROM runtime.active_locks;    -- advisory lock holders
```

### Message contract

Single JSONB envelope, routed by top-level `type`:

```jsonc
// type = "market"
{ "type": "market", "slug": "...", "question": "...",
  "yes_price": 0.42, "no_price": 0.58, "volume_24h": 12345,
  "category": "...", "end_date": "2026-05-01T00:00:00Z",
  "fetched_at": "2026-04-21T12:00:00Z" }

// type = "price"
{ "type": "price", "coin": "bitcoin",
  "price_usd": 97000, "change_24h": -1.2,
  "fetched_at": "2026-04-21T12:00:00Z" }
```

---

## 4. How the proxy will call the queue

On `dev`, the proxy currently dials `RABBITMQ_URL` unconditionally and publishes `market` / `price` JSON via `channel.Publish` on the `market_events` queue (`proxy/main.go`). The target cut-over adds a `RUNTIME_BACKEND` (`external` | `postgres`) selector at startup:

- **`external` mode** (default until `postgres` is verified) — keeps `RABBITMQ_URL` and the current `channel.Publish(...)` path. This is current `dev` behavior, preserved intentionally for the staged rollout in #9/#10/#11.
- **`postgres` mode** — uses `DATABASE_URL` and `SELECT runtime.enqueue_event($1::jsonb)` over `pgx` instead of AMQP. Payload shape is unchanged, so the existing history consumer accepts it as-is.

`RABBITMQ_URL` stays configured through the `external` phase and is removed from deployment only after `postgres` mode is verified end-to-end in production — not in the release that first ships the branch.

## 5. How the consumer will call the queue

The deployed consumer on `node-01` is currently `history/consumer.py` — RabbitMQ-backed, routes messages by `type` into `market_snapshots` / `price_snapshots` with `ON CONFLICT DO NOTHING`. Ansible on `dev` deploys only this path. The replacement — `runtime/runtime_consumer.py`, merged on `dev` via PR #23 — reads from `pgmq` but is not deployed.

Under the `RUNTIME_BACKEND` selector from §4, Ansible will deploy `history/consumer.py` in `external` mode and `runtime/runtime_consumer.py` in `postgres` mode. Both paths write idempotently to the same snapshot tables, so the switch is a deployment-time choice with no schema or data migration.

Reference flow (`runtime/runtime_consumer.py`):

```text
main loop (defaults: BATCH=10, VT=30s, MAX_RETRIES=3, LISTEN_TIMEOUT=5s):
  1. runtime.advisory_try_lock(1)          -- else read-only standby
  2. LISTEN runtime_events
  3. for msg in runtime.claim_events(BATCH, VT):
         try:
             INSERT INTO market_snapshots | price_snapshots ... ON CONFLICT DO NOTHING
             runtime.ack_event(msg.msg_id)
         except Exception as e:
             runtime.fail_event(msg.msg_id, str(e), MAX_RETRIES)
  4. select() on the connection, LISTEN_TIMEOUT seconds; drain conn.notifies
  5. goto 3
```

Crash recovery: systemd `Restart=on-failure`. The advisory lock dies with the session; unacked messages become claimable once their visibility timeout expires.

---

## 6. Cache & session API

This section defines the accepted target design. None of the SQL below is on `dev` yet; implementation is tracked by #18 on branch `feature/postgres-runtime-cache`. On current `dev`, whales and prices live in the proxy's in-process Go cache (`Server.cache` guarded by `sync.RWMutex` in `proxy/main.go`, refreshed every 5 min and 10 s respectively), and Redis on `node-02` holds only `/state` sessions (`session:{sid}`, 24 h TTL).

### Tables

```sql
-- Generic TTL key/value cache. UNLOGGED: no WAL, truncated on crash.
CREATE UNLOGGED TABLE runtime.cache (
    key        TEXT        PRIMARY KEY,
    value      JSONB       NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX cache_expires_at_idx ON runtime.cache (expires_at);

-- Proxy session state (replaces Redis `session:{sid}`).
-- UNLOGGED mirrors current Redis behaviour (sessions die on node restart);
-- promote to LOGGED later if/when session durability becomes a requirement.
CREATE UNLOGGED TABLE runtime.session (
    sid        TEXT        PRIMARY KEY,
    data       JSONB       NOT NULL,
    expires_at TIMESTAMPTZ NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX session_expires_at_idx ON runtime.session (expires_at);
```

### Functions

```sql
-- Cache
runtime.cache_set   (p_key TEXT, p_value JSONB, p_ttl INTERVAL) RETURNS VOID
runtime.cache_get   (p_key TEXT)                                 RETURNS JSONB   -- NULL if missing or expired
runtime.cache_delete(p_key TEXT)                                 RETURNS BOOLEAN -- true if a row was removed
runtime.cache_reap  ()                                           RETURNS INT     -- deletes rows WHERE expires_at <= now()

-- Session (thin wrappers; same contract, different table)
runtime.session_set   (p_sid TEXT, p_data JSONB, p_ttl INTERVAL) RETURNS VOID
runtime.session_get   (p_sid TEXT)                               RETURNS JSONB
runtime.session_delete(p_sid TEXT)                               RETURNS BOOLEAN
runtime.session_reap  ()                                         RETURNS INT
```

**Semantics.**
`cache_set` is an UPSERT — `INSERT ... ON CONFLICT (key) DO UPDATE`. `cache_get` filters `WHERE expires_at > now()`, so expired rows are invisible even before the reaper runs. `*_reap` is what `pg_cron` calls, and it deletes `WHERE expires_at <= now()` — the `<=` matches the strict `>` in `cache_get` so a boundary row is invisible to readers and reaped in the same tick.

### Privileges

All wrappers are `SECURITY DEFINER`. To prevent any role with `CONNECT` on the database from invoking `session_delete` / `cache_set` / etc. as the wrapper owner, bootstrap runs:

```sql
REVOKE EXECUTE ON FUNCTION
    runtime.cache_set(TEXT, JSONB, INTERVAL),
    runtime.cache_get(TEXT),
    runtime.cache_delete(TEXT),
    runtime.cache_reap(),
    runtime.session_set(TEXT, JSONB, INTERVAL),
    runtime.session_get(TEXT),
    runtime.session_delete(TEXT),
    runtime.session_reap()
FROM PUBLIC;

-- Grant only to the role named by the runtime.app_role GUC; fail-closed if unset.
DO $$
DECLARE v_role TEXT := current_setting('runtime.app_role', true);
BEGIN
    IF v_role IS NULL OR v_role = '' THEN
        RAISE NOTICE 'runtime.app_role not set — skipping GRANT EXECUTE';
        RETURN;
    END IF;
    EXECUTE format('GRANT EXECUTE ON FUNCTION runtime.cache_set(...), ... TO %I', v_role);
END $$;
```

The GUC is set once per database, before the wrappers are loaded:

```sql
ALTER DATABASE <db> SET runtime.app_role = 'cognitor_app';
```

**Deploy ordering matters.** Set the GUC before loading `runtime/07_cache_wrappers.sql`, or re-run the file after setting it. A fresh bootstrap without the GUC runs the REVOKE, skips the GRANT, and the proxy gets permission-denied on its first `runtime.cache_*` call.

### Scheduled jobs (pg_cron)

```sql
-- Cache: reap every minute (matches current 60 s price TTL granularity).
SELECT cron.schedule_in_database('runtime-cache-reap',   '* * * * *',
                                 $$SELECT runtime.cache_reap()$$,   current_database());

SELECT cron.schedule_in_database('runtime-session-reap', '*/5 * * * *',
                                 $$SELECT runtime.session_reap()$$, current_database());

-- DLQ: nightly purge of audit rows older than 30 days.
SELECT cron.schedule_in_database('runtime-dlq-reap',     '0 3 * * *',
                                 $$SELECT runtime.dlq_reap_expired('30 days')$$, current_database());
```

**Launcher vs. execution database — a required invariant.** `pg_cron` runs a single launcher background worker that reads job metadata from exactly one database, the one named by `cron.database_name` in `postgresql.conf` (default: `postgres`). `cron.schedule_in_database(..., current_database())` only changes the database the *command body* executes in; it does not change which database the launcher watches. Installing `pg_cron` in the application database without also setting `cron.database_name` to that same database therefore registers jobs successfully in `cron.job` but never fires them. The invariant this design depends on is:

> `pg_cron` MUST be installed in the application database, AND `cron.database_name` MUST be set to that same database.

Both conditions are enforced at the image layer (`shared_preload_libraries = 'pg_cron,pgmq'` and `cron.database_name = 'cognitor'` in `postgresql.conf`, see §9.1). With the invariant held, a fresh DB boot autostarts the reapers from the bootstrap SQL with no manual step. Smoke test 15 in `runtime/tests/test_runtime.sql` inserts an expired sentinel row and fails if it is not physically reaped within ~90 s, which is the end-to-end check that catches any misconfiguration of this invariant.

---

## 7. How the proxy will call the cache

The "Current" column maps the actual call sites in `proxy/main.go` on `dev`; the "After" column is the target under `RUNTIME_BACKEND=postgres`.

| Current (on `dev`) | After postgres cut-over |
|---|---|
| `s.cache.whales` — in-process Go slice, refreshed every 5 min under `sync.RWMutex` (`proxy/main.go`) | `runtime.cache_get / cache_set('whales', …, '5 minutes')` |
| `s.cache.prices` — in-process Go struct, refreshed every 10 s under `sync.RWMutex` (`proxy/main.go`) | `runtime.cache_get / cache_set('prices:btc-eth-uah', …, '60 seconds')` |
| `s.cache.markets` — in-process, 60 s refresh | Remains in proxy memory; not part of this migration |
| `rdb.Get(ctx, "session:"+sid)` — Redis, 24 h TTL (`proxy/main.go` `/state` handler) | `runtime.session_get($1)` |
| `rdb.Set(ctx, "session:"+sid, json, 24 h)` | `runtime.session_set($1, $2::jsonb, '24 hours')` |
| Redis `Ping` health check | `SELECT 1` on the same `DATABASE_URL` |

Note the asymmetry: **whales and prices move from in-process memory into `runtime.cache`** (they were never in Redis), while **only `/state` sessions move off Redis**. Markets stay in proxy memory regardless.

**Staged cut-over.** The same `RUNTIME_BACKEND` flag from §4 governs the cache/session path: in `external` mode the proxy keeps the in-process cache and Redis sessions; in `postgres` mode it calls `runtime.cache_*` / `runtime.session_*`. `REDIS_URL` stays configured through the `external` phase and is removed from deployment only after `postgres`-mode session reads/writes are verified in production.

---

## 8. Limits vs RabbitMQ / Redis

| Dimension | Postgres runtime (this ADR) | RabbitMQ (current) | Redis (current) |
|---|---|---|---|
| **Transport — ordering** | FIFO per queue | FIFO per queue | FIFO (lists) |
| **Transport — persistence** | WAL-durable (pgmq) | Durable queues with fsync | AOF best-effort |
| **Transport — throughput** | ~5–10k msg/s | 100k+ msg/s | very high (non-durable) |
| **Transport — delivery** | At-least-once + idempotent writes | At-least-once (manual ack) | n/a |
| **Transport — DLQ** | `events_dlq` + `dead_letter_audit`, queryable in SQL | `x-dead-letter-exchange` policy | n/a |
| **Transport — fan-out** | Not supported by design (single consumer) | Exchanges + bindings | Pub/Sub |
| **Cache — persistence** | `UNLOGGED` (crash-truncated, same as Redis without AOF) | n/a | RDB/AOF snapshots |
| **Cache — TTL enforcement** | `expires_at` column + pg_cron reaper; reads also filter | n/a | Built-in expirer |
| **Cache — throughput** | Bound by Postgres; ample for our hit rate | n/a | 100k+ ops/s |
| **Session — durability** | `UNLOGGED` initially; flip to `LOGGED` if required | n/a | RDB/AOF |
| **Observability** | Plain SQL across queue/cache/session/DLQ | RabbitMQ UI | `redis-cli` |
| **Backpressure** | Consumer pull; `runtime.queue_depth` monitored | Channel-level flow control | None |

Our workload sits far below every ceiling here — a few events/sec, a handful of cache keys with second-scale TTLs. Throughput is not the constraint; the trade we are making is operational simplicity for raw scalability headroom.

---

## 9. Operational notes

The items below describe the infrastructure changes that land with the `RUNTIME_BACKEND=postgres` rollout. None of them are on `dev` yet: Ansible provisions stock Postgres on `node-01` alongside RabbitMQ, does not apply `runtime/00_run_all.sql`, and does not schedule `pg_cron` jobs.

1. **Base image.** `node-01` Postgres will run a custom image:

  ```Dockerfile
  FROM quay.io/tembo/pg16-pgmq:latest
  RUN apt-get update \
   && apt-get install -y postgresql-16-cron \
   && rm -rf /var/lib/apt/lists/*
  # pg_cron must be preloaded; pgmq is already set by the base. The launcher
  # bgworker binds to exactly one DB (see §6) so cron.database_name must be
  # pinned to the application DB here — jobs registered elsewhere are inert.
  RUN printf "shared_preload_libraries = 'pg_cron,pgmq'\ncron.database_name = 'cognitor'\n" \
      >> /usr/share/postgresql/postgresql.conf.sample
  ENV POSTGRES_DB=cognitor
  ```
  
2. Published under our own registry; Ansible/Terraform rollout tracked as an infra follow-up.
3. **Extensions.** Bootstrap SQL runs `CREATE EXTENSION IF NOT EXISTS pgmq; CREATE EXTENSION IF NOT EXISTS pg_cron;`.
4. **Staged verification and rollback.** The `RUNTIME_BACKEND=external|postgres` flag from §4/§7 is the primary mechanism for staged rollout *and* rollback: environments stay on `external` (RabbitMQ + Redis + in-process cache) until `postgres` is verified, and fall back by flipping the flag. For higher confidence during the cut-over release, the proxy may dual-publish to RabbitMQ and pgmq / dual-write to Redis and `runtime.cache` for a bounded window — no event-schema migration is required either way.

---

## 10. Consequences

| Positive                                                                                          | Negative / trade-offs                                                                                 |
| ------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------- |
| Two services disappear: RabbitMQ on node-01, Redis on node-02.                                    | Every runtime workload now funnels through one database — capacity planning on Postgres matters more. |
| Queue, cache, sessions, and their failures are all inspectable via SQL — one tool, one auth path. | We own a custom Docker image (`pgmq + pg_cron`). It must be kept in sync with upstream Tembo.         |
| Enqueue and cache mutations can participate in Postgres transactions.                             | Operators need `runtime.*` SQL fluency instead of a GUI.                                              |

---

## 11. References

- Queue implementation: `runtime/01_schema.sql` … `runtime/05_dlq.sql`, `runtime/runtime_consumer.py` (branch `postgres-runtime-queue`).
- Queue design walkthrough: [`docs/runtime-queue-architecture.md`](../runtime-queue-architecture.md).
- `pgmq`: https://github.com/tembo-io/pgmq.
- `pg_cron`: https://github.com/citusdata/pg_cron.
