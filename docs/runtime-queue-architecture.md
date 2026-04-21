# Runtime Queue Architecture (PostgreSQL + pgmq)

> **Branch:** `feature/postgres-runtime-queue`  
> **Goal:** Replace the RabbitMQ hop for internal event delivery with a pure-PostgreSQL queue backed by [pgmq](https://github.com/tembo-io/pgmq), adding reliable retries, dead-letter handling, LISTEN/NOTIFY wake-up, and advisory-lock-based single-consumer coordination.

---

## Table of Contents

1. [Motivation](#1-motivation)
2. [High-Level Design](#2-high-level-design)
3. [Component Map](#3-component-map)
4. [Schema Overview](#4-schema-overview)
5. [API Reference](#5-api-reference)
6. [Dead-Letter Queue](#6-dead-letter-queue)
7. [LISTEN / NOTIFY Wake-up](#7-listen--notify-wake-up)
8. [Advisory Locks](#8-advisory-locks)
9. [Python Consumer](#9-python-consumer)
10. [Message Contract](#10-message-contract)
11. [Deployment & Migration](#11-deployment--migration)
12. [Acceptance Criteria Verification](#12-acceptance-criteria-verification)
13. [Operational Runbook](#13-operational-runbook)

---

## 1. Motivation

The current architecture routes all market and price events through RabbitMQ (node-01:5672). While RabbitMQ works, it introduces:

| Pain point | Impact |
|---|---|
| Extra service to operate | RabbitMQ requires its own VM, memory, monitoring |
| Network hop between nodes | Adds latency + failure surface |
| Two separate persistence stores | Data lives in both RabbitMQ and PostgreSQL |
| Dead-letter logic is RabbitMQ-specific | Not portable, harder to inspect |

Because PostgreSQL is already the system of record, **pgmq gives us a transactional, durable event queue inside the same DB** — no extra infra, no new failure mode, SQL-native observability.

---

## 2. High-Level Design

```
Proxy Service (Go)
  /current, /prices -> normalise -> runtime.enqueue_event()
                                         |
                                    pg_notify('runtime_events', msg_id)
                                         |
              consumer waits via  LISTEN runtime_events
                   |
           runtime_consumer.py
              1. advisory_try_lock(1)   <- single-consumer lock
              2. drain_batch():
                 |- claim_events(N, vt) <- pgmq read (hidden window)
                 |- process_message()   <- INSERT market_snapshots / price_snapshots
                 |- ack_event()         <- pgmq.delete + cleanup
                 `- fail_event()        <- retry / DLQ promotion
              3. wait_for_notify()       <- block on socket (no hot-poll)
                   |
             (after MAX_RETRIES)
             events_dlq + dead_letter_audit
```

**Key properties:**

- **At-least-once delivery.** If the consumer crashes before calling `ack_event()`, the visibility timeout expires and the message becomes claimable again.
- **Exactly-once writes.** `ON CONFLICT DO NOTHING` ensures duplicate redeliveries are safely discarded.
- **No hot-polling.** `LISTEN runtime_events` + `select()` blocks on the socket until a message arrives.
- **Single active consumer.** `advisory_try_lock(1)` prevents two replicas from double-consuming the same batch.

---

## 3. Component Map

```
runtime/
+-- 00_run_all.sql          <- master bootstrap (runs 01-05 in order)
+-- 01_schema.sql           <- CREATE SCHEMA runtime, pgmq extension, tables
+-- 02_wrappers.sql         <- enqueue / claim / ack / fail functions
+-- 03_notify.sql           <- LISTEN/NOTIFY trigger + queue_depth view
+-- 04_advisory.sql         <- advisory lock helpers + active_locks view
+-- 05_dlq.sql              <- DLQ inspect / replay / purge functions
+-- runtime_consumer.py     <- Python consumer (replaces consumer.py)
`-- tests/
    `-- test_runtime.sql    <- SQL acceptance tests
```

---

## 4. Schema Overview

### Tables

#### `runtime.event_retry`

| Column | Type | Description |
|--------|------|-------------|
| `msg_id` | BIGINT PK | pgmq message id in `events` queue |
| `queue_name` | TEXT | always `events` (extensible) |
| `attempt_count` | INT | incremented by `fail_event()` |
| `last_error` | TEXT | last error string from consumer |
| `last_failed_at` | TIMESTAMPTZ | when was the last failure |
| `created_at` | TIMESTAMPTZ | when was the message first enqueued |

#### `runtime.dead_letter_audit`

| Column | Type | Description |
|--------|------|-------------|
| `id` | BIGSERIAL PK | internal audit id |
| `original_msg_id` | BIGINT | original pgmq msg_id |
| `queue_name` | TEXT | source queue name |
| `payload` | JSONB | copy of the message payload |
| `last_error` | TEXT | final error that triggered DLQ |
| `attempt_count` | INT | total attempts before DLQ |
| `dead_at` | TIMESTAMPTZ NOT NULL | when promoted to DLQ — always set, never nulled |
| `replayed_at` | TIMESTAMPTZ (nullable) | set when re-enqueued via `dlq_replay`; NULL = still poisoned |

#### `runtime.advisory_lock_keys`

Registry of advisory lock ids.

| `lock_key` | `description` |
|---|---|
| 1 | `single-consumer-events` |
| 2 | `schema-migration` |
| 3 | `dlq-reaper` |

### pgmq Queues

| Queue | Purpose |
|-------|---------|
| `events` | Primary queue — all market + price events |
| `events_dlq` | Dead-letter queue — poison events after N retries |

Both are **durable**: pgmq stores rows in PostgreSQL tables, covered by WAL replay.

### Monitoring Views

| View | Description |
|------|-------------|
| `runtime.queue_depth` | Live msg count + age for events and events_dlq |
| `runtime.active_locks` | Sessions holding runtime advisory locks |

---

## 5. API Reference

### `runtime.enqueue_event(payload JSONB) -> BIGINT`

1. `pgmq.send('events', payload)` assigns a `msg_id`
2. Inserts a row into `runtime.event_retry` (attempt_count = 0)
3. `pg_notify('runtime_events', msg_id::TEXT)` wakes consumers
4. Returns the `msg_id`

```sql
SELECT runtime.enqueue_event('{"type":"market","slug":"btc-100k","yes_price":0.62}');
```

---

### `runtime.claim_events(p_n INT, p_vt INT) -> SETOF pgmq.message_record`

- Calls `pgmq.read('events', p_vt, p_n)`
- Claimed messages are **hidden** from other consumers for `p_vt` seconds
- If not acked within `p_vt`, they re-appear (at-least-once guarantee)

**Columns returned:**

| Column | Type | Description |
|--------|------|-------------|
| `msg_id` | BIGINT | Unique message id |
| `read_ct` | INT | Re-delivery count |
| `enqueued_at` | TIMESTAMPTZ | When enqueue_event was called |
| `vt` | TIMESTAMPTZ | Visibility timeout expires at |
| `message` | JSONB | The payload |

---

### `runtime.ack_event(p_msg_id BIGINT) -> VOID`

1. `pgmq.delete('events', p_msg_id)` — permanently removes from queue
2. Deletes matching row from `runtime.event_retry`

Call this **after** a successful database write (at-least-once semantics).

---

### `runtime.fail_event(p_msg_id BIGINT, p_error TEXT, p_max_tries INT) -> VOID`

Decision tree:

```
attempt_count < p_max_tries ?
  YES -> pgmq.set_vt(exponential_backoff)
  NO  -> pgmq.send('events_dlq', payload)
         INSERT INTO runtime.dead_letter_audit
         pgmq.delete('events', msg_id)
         DELETE FROM runtime.event_retry
```

**Backoff schedule** (`min(120, 5 x 2^attempt)` seconds):

| Attempt | Delay |
|---------|-------|
| 1st | 10 s |
| 2nd | 20 s |
| 3rd | 40 s -> DLQ (if max=3) |

---

## 6. Dead-Letter Queue

### Message lifecycle

```
enqueue_event()
      |
  [events queue]
      |
  fail_event (1st) -> re-visible after 10s
  fail_event (2nd) -> re-visible after 20s
  fail_event (3rd) -> events_dlq + dead_letter_audit
```

### DLQ management functions

| Function | Description |
|----------|-------------|
| `runtime.dlq_pending(limit, vt)` | List / claim DLQ messages |
| `runtime.dlq_replay(dlq_msg_id)` | Move one message back to events |
| `runtime.dlq_discard(dlq_msg_id)` | Permanently delete a DLQ message |
| `runtime.dlq_replay_all()` | Replay all DLQ messages (advisory lock 3) |
| `runtime.dlq_reap_expired(interval)` | Purge old DLQ audit entries |

```sql
-- Inspect audit log
SELECT original_msg_id, payload->>'slug', last_error, attempt_count, dead_at
FROM runtime.dead_letter_audit ORDER BY dead_at DESC LIMIT 20;

-- Replay everything
SELECT runtime.dlq_replay_all();

-- Scheduled purge (30 days)
SELECT runtime.dlq_reap_expired('30 days');
```

---

## 7. LISTEN / NOTIFY Wake-up

### Why

Without NOTIFY, the consumer must poll the queue table every N ms — wasting CPU and DB connections at low event rates.

With NOTIFY: consumer blocks on the OS socket (zero CPU) and wakes within ~1 ms of each new event.

### Mechanism

```
enqueue_event() commits
        |
        `- AFTER INSERT trigger (trg_runtime_events_notify)
                fires notify_on_event_enqueue()
                    calls pg_notify('runtime_events', msg_id)
                        |
                        v
              consumer's LISTEN connection unblocks
              conn.poll() drains conn.notifies
              drain_batch() claims the new messages
```

### Consumer-side Python

```python
# Once on startup
cur.execute("LISTEN runtime_events")

# In the main loop
if select.select([conn], [], [], LISTEN_TIMEOUT)[0]:
    conn.poll()
    while conn.notifies:
        conn.notifies.pop(0)   # flush; drain_batch reads actual data
```

> The NOTIFY payload (msg_id) is informational. The consumer always calls `claim_events()` to get the full batch — it does not trust the raw NOTIFY value.

### Trigger placement

`03_notify.sql` probes both `public.q_events` and `pgmq.q_events` (different pgmq install layouts) and attaches the trigger to whichever exists, printing a NOTICE for confirmation.

---

## 8. Advisory Locks

### Purpose

Ensure only one consumer replica claims events concurrently — preventing duplicate processing.

### Namespace

Fixed prefix `0x52554E54` (ASCII "RUNT", decimal `1415865428`). Prevents collisions with other extensions using advisory locks.

### Lock ids

| Key | Name | Holder |
|-----|------|--------|
| 1 | `single-consumer-events` | `runtime_consumer.py` |
| 2 | `schema-migration` | migration tooling |
| 3 | `dlq-reaper` | `dlq_replay_all()` |

### API

```sql
-- Non-blocking (recommended for consumers)
SELECT runtime.advisory_try_lock(1);    -- TRUE = acquired, FALSE = another holds it

-- Blocking
SELECT runtime.advisory_lock(1);

-- Release
SELECT runtime.advisory_unlock(1);

-- Release all (use in teardown handlers)
SELECT runtime.advisory_unlock_all();

-- Inspect active holders
SELECT * FROM runtime.active_locks;
```

### Multi-replica behaviour

```
Replica A: advisory_try_lock(1) -> TRUE  -> active consumer
Replica B: advisory_try_lock(1) -> FALSE -> standby mode

Replica A crashes -> session ends -> lock released automatically
Replica B: next try -> TRUE -> takes over
```

---

## 9. Python Consumer

`runtime/runtime_consumer.py` is a drop-in replacement for `history/consumer.py`.

### Comparison with old consumer

| Feature | Old (RabbitMQ / pika) | New (pgmq / psycopg2) |
|---------|-----------------------|----------------------|
| Transport | AMQP | PostgreSQL |
| Wake-up | pika event loop | `LISTEN` + `select()` |
| Retry | `basic_nack(requeue=True)` | `fail_event()` with exponential backoff |
| DLQ | `basic_publish` to dead queue | Automatic after MAX_RETRIES |
| Single-consumer | Not enforced | `advisory_try_lock(1)` |
| Connections | AMQP + PostgreSQL | Single PostgreSQL (AUTOCOMMIT) |

### Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `DATABASE_URL` | required | psycopg2 connection string |
| `BATCH_SIZE` | `10` | Messages claimed per loop |
| `VT_SECONDS` | `30` | Visibility timeout (seconds) |
| `MAX_RETRIES` | `3` | Failures before DLQ promotion |
| `LISTEN_TIMEOUT` | `5` | Seconds to block on NOTIFY |

### Run

```bash
DATABASE_URL="postgres://user:pass@node-01/coinops" python runtime/runtime_consumer.py
```

### Systemd unit

```ini
[Unit]
Description=Coin-Ops Runtime Queue Consumer
After=postgresql.service

[Service]
User=cognitor
EnvironmentFile=/opt/cognitor/.env
ExecStart=/opt/cognitor/history/venv/bin/python /opt/cognitor/runtime/runtime_consumer.py
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

---

## 10. Message Contract

Identical to the existing RabbitMQ contract. **No changes to the Go Proxy required.**

### Market snapshot

```json
{
  "slug":       "will-bitcoin-reach-100k-by-june-2026",
  "question":   "Will Bitcoin reach $100k by June 2026?",
  "yes_price":  0.62,
  "no_price":   0.38,
  "volume_24h": 184000.00,
  "category":   "Crypto",
  "end_date":   "2026-06-30T23:59:00Z",
  "fetched_at": "2026-04-21T12:00:00Z"
}
```

Routes to: `INSERT INTO market_snapshots ... ON CONFLICT DO NOTHING`

### Price event

```json
{
  "type":       "price",
  "coin":       "bitcoin",
  "price_usd":  97000.00,
  "change_24h": -1.2,
  "fetched_at": "2026-04-21T12:00:00Z"
}
```

Routes to: `INSERT INTO price_snapshots ... ON CONFLICT DO NOTHING`

### Malformed message flow

`json.loads()` fails -> `fail_event()` on attempt 1 -> after `MAX_RETRIES`: raw payload lands in `events_dlq` + `dead_letter_audit`.

---

## 11. Deployment & Migration

### Prerequisites

```bash
# Install pgmq extension (Ubuntu/Debian + PostgreSQL 16):
apt-get install postgresql-16-pgmq
# Alternative: https://github.com/tembo-io/pgmq
```

### Step 1: Apply runtime schema

```bash
psql $DATABASE_URL -f runtime/00_run_all.sql
```

Fully idempotent — safe to re-run.

### Step 2: Verify

```sql
SELECT * FROM runtime.queue_depth;
SELECT runtime.enqueue_event('{"type":"market","slug":"test","yes_price":0.5}');
SELECT * FROM runtime.claim_events(1, 30);
```

### Step 3: Run acceptance tests

```bash
psql $DATABASE_URL -f runtime/tests/test_runtime.sql
```

Expected: `PASS test1 ... PASS test6 ... === all tests passed ===`

### Step 4: Switch consumer

```bash
systemctl stop history-consumer
systemctl start runtime-consumer
```

### Step 5: Migrate Go Proxy (last step, optional)

```go
// Before (RabbitMQ):
ch.Publish("", "market_events", false, false, amqp.Publishing{Body: body})

// After (pgmq via SQL):
db.Exec(`SELECT runtime.enqueue_event($1)`, body)
```

> Until the Go proxy is updated, both consumers can co-exist. `ON CONFLICT DO NOTHING` prevents double-writes.

---

## 12. Acceptance Criteria Verification

| AC | Satisfied by |
|----|-------------|
| Can enqueue via SQL | `runtime.enqueue_event(payload)` returns msg_id |
| Can claim via SQL | `runtime.claim_events(n, vt)` returns pgmq.message_record rows |
| Can ack via SQL | `runtime.ack_event(id)` deletes from queue + retry table |
| Can fail via SQL | `runtime.fail_event(id, err)` increments counter, reschedules with backoff |
| Malformed event lands in DLQ after N retries | `fail_event()` with `attempt_count >= MAX_RETRIES` promotes to events_dlq + audit row |
| LISTEN wakes when new event arrives | `trg_runtime_events_notify` fires `pg_notify` on INSERT; consumer uses `LISTEN` + `select()` |

Run `runtime/tests/test_runtime.sql` to verify all 6 ACs automatically.

---

## 13. Operational Runbook

### Monitor queue depth

```sql
SELECT * FROM runtime.queue_depth;
```

### Inspect DLQ audit log

```sql
-- Active (un-replayed) dead-letter entries, newest first
SELECT original_msg_id, payload->>'slug', last_error, attempt_count, dead_at
FROM runtime.dead_letter_audit
WHERE replayed_at IS NULL
ORDER BY dead_at DESC;

-- Already-replayed entries (audit history)
SELECT original_msg_id, dead_at, replayed_at
FROM runtime.dead_letter_audit
WHERE replayed_at IS NOT NULL
ORDER BY replayed_at DESC;
```

### Replay all DLQ messages

```sql
SELECT runtime.dlq_replay_all();
```

### Replay a specific DLQ message

```sql
SELECT runtime.dlq_replay(42);  -- 42 = dlq msg_id from dead_letter_audit
```

### Discard an unrecoverable message

```sql
SELECT runtime.dlq_discard(42);
```

### Check advisory lock holders

```sql
SELECT * FROM runtime.active_locks;
```

### Kill a stuck consumer (releases advisory lock automatically on session end)

```sql
SELECT pg_terminate_backend(pid)
FROM runtime.active_locks
WHERE lock_name = 'single-consumer-events';
```

### Scheduled DLQ purge via pg_cron

```sql
SELECT cron.schedule(
    'dlq-reap-30d',
    '0 3 * * *',
    $$SELECT runtime.dlq_reap_expired('30 days')$$
);
```
