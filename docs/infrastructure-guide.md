# Infrastructure Guide

An educational walkthrough of how this system is put together and why each piece exists. Written for DevOps interns who have built apps but not yet run a distributed system across multiple machines.

Every decision here has a "why". The "what" is the easy part — you can look it up. The "why" is what separates someone who can copy a tutorial from someone who can debug production at 2am.

---

## 1. System Overview

The Polymarket Intelligence Dashboard runs as three cooperating services on three separate Ubuntu VMs.

| VM | IP | Role | Why it lives here |
|----|----|------|-------------------|
| node-01 | 172.31.1.10 | PostgreSQL + RabbitMQ + History Consumer + History API | The "storage" box. Everything that persists data or reads it back is here. Putting PostgreSQL and RabbitMQ on the same VM avoids a network hop between the consumer and both of its dependencies. |
| node-02 | 172.31.1.11 | Proxy Service (Go) + Redis | The "edge" box. The proxy is the only service that talks to the outside world (Gamma, CoinGecko, NBU). Redis is colocated because it stores only session state used by the proxy — it needs to be close, not durable. |
| node-03 | 172.31.1.12 | Web UI (nginx, static HTML) | The "presentation" box. Serves only static files. Zero business logic lives here. |

### Why three services, not one?

A single monolithic process would be simpler to write but worse to operate:

- **Independent scaling.** If users hammer the UI, you add nginx capacity. If the history API is slow, you add a read replica. You do not need to scale Redis just because CoinGecko is slow.
- **Independent failure.** If the history consumer crashes, the proxy keeps serving `/current`. Users still see live markets. Their session state still works. Only the "History" tab degrades.
- **Independent deployment.** You can push a UI-only change without restarting the proxy or the queue consumer. The blast radius of each deploy matches the scope of the change.
- **Blast radius of bugs.** A memory leak in the proxy does not corrupt the database. A slow SQL query does not block the UI's live-market fetches.

### What would break if we merged everything onto one VM?

- **One reboot kills everything.** Today, rebooting node-03 for a kernel update does not interrupt data ingestion. Merged, it would.
- **Resource contention.** A CoinGecko fetch stall holds an HTTP handler; if PostgreSQL is in the same process's event loop, queries start backing up too.
- **Deploy coupling.** A nginx config typo would take down the proxy.
- **Security posture.** Redis currently binds to localhost on node-02, reachable only by the proxy. Merged, the same Redis would sit next to nginx (public-facing port 80), which enlarges the attack surface.

The "three services across three VMs" shape is the smallest useful distributed system. It teaches you the concepts (network boundaries, message queues, shared state) without being overwhelming.

---

## 2. Network Topology

### Static IPs via netplan

Every VM has a hardcoded static IP set in `/etc/netplan/*.yaml`. No DHCP.

Why static?
- **Ansible's inventory file maps hostnames to IPs.** If IPs change on reboot, every play breaks.
- **RabbitMQ / PostgreSQL connection strings hardcode the node-01 IP.** If node-01's IP drifts, the proxy and consumer can no longer connect.
- **Troubleshooting is reproducible.** `ssh vagrant@172.31.1.10` always means node-01. No lookup step.

DHCP is fine for end-user workstations. For servers that other servers depend on, static IPs (or a proper DNS layer, which we don't have here) are the right default.

### ASCII diagram

```
     ┌──────────────────────────────────────────────────────────────┐
     │                       Browser (anywhere)                     │
     └────────────┬──────────────────┬──────────────────┬───────────┘
                  │                  │                  │
                  │ :80              │ :8080            │ :8000
                  ▼                  ▼                  ▼
     ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐
     │   node-03 UI     │  │  node-02 Proxy   │  │ node-01 History  │
     │  172.31.1.12     │  │  172.31.1.11     │  │  172.31.1.10     │
     │  nginx :80       │  │  Go :8080        │  │  FastAPI :8000   │
     │                  │  │  Redis :6379     │  │  PostgreSQL :5432│
     │                  │  │  (localhost)     │  │  RabbitMQ :5672  │
     │                  │  │                  │  │  Consumer (bg)   │
     └──────────────────┘  └────────┬─────────┘  └──────────┬───────┘
                                    │ AMQP :5672            │
                                    └───────────────────────┘
```

### Which ports are open on which VM (UFW rules)

| VM | Open ports | Closed |
|----|------------|--------|
| node-01 | 22 (SSH), 5432 (PostgreSQL), 5672 (AMQP), 8000 (History API) | everything else |
| node-02 | 22 (SSH), 8080 (Proxy) | 6379 (Redis — listens on 127.0.0.1 only, not firewalled open) |
| node-03 | 22 (SSH), 80 (nginx) | everything else |

UFW is set to **default-deny**. You explicitly allow only what needs to be reachable. This is the opposite of "allow everything, block the bad stuff" — and the opposite is correct for servers.

### Why Redis binds to localhost only

The proxy and Redis run on the same VM (node-02). The proxy connects via `localhost:6379`. No other service needs to touch Redis.

If Redis bound to `0.0.0.0`, it would be reachable from anywhere on the subnet. Redis has no authentication by default. That is an open door.

Defense in depth: even if someone punched a hole in UFW by mistake, Redis still would not answer. Both layers must fail for Redis to be exposed.

### Why the browser talks to two different VMs

- **Proxy (node-02:8080)** serves *live data* — current markets, whale positions, prices, session state. It's the thing the UI hits on every refresh tick.
- **History API (node-01:8000)** serves *stored data* — historical snapshots read from PostgreSQL. The UI hits it on demand (user clicks a chart).

Splitting them means a slow PostgreSQL query never blocks a live-market refresh. And the proxy never has to hold a database connection — its entire job is "fetch → normalize → publish → return".

---

## 3. Ansible Explained

Ansible is how we configure machines without SSHing in and typing commands. You describe the desired state in YAML, run a playbook, and Ansible makes the machine match.

### Inventory

`ansible/inventory` maps hostnames to IPs and groups hosts into logical sets:

```ini
[history]
softserve-node-01 ansible_host=172.31.1.10

[proxy]
softserve-node-02 ansible_host=172.31.1.11

[ui]
softserve-node-03 ansible_host=172.31.1.12
```

When you run `ansible-playbook deploy.yml`, Ansible reads this file to know who to connect to and what group each host belongs to.

### group_vars hierarchy

Variables are layered from least specific to most specific:

```
ansible/group_vars/
  all/              ← applies to every host (non-secret shared config)
  history/          ← applies only to [history] group
  proxy/            ← applies only to [proxy] group
  ui/               ← applies only to [ui] group
ansible/host_vars/
  softserve-node-01.yml   ← applies to just one host (SSH key path, etc.)
```

Lower specificity first, higher overrides. `host_vars` wins over `group_vars`, which wins over `all`.

### secrets.yml vs secrets.example.yml

- `secrets.yml` — real passwords, gitignored, lives on your workstation only.
- `secrets.example.yml` — committed template with placeholder values. Shows the structure someone needs to fill in.

Why this matters: git history is forever. A password committed once lives in the repo until the end of time — even if you delete it in the next commit. Every clone still has it. The `.example` pattern means new team members know what variables exist without ever seeing the real values.

### Role structure

Each role (`roles/common`, `roles/proxy`, `roles/history`, `roles/ui`) has a standard layout:

- `tasks/` — the list of things to do (install packages, write files, start services).
- `handlers/` — actions triggered by `notify:` on a task. Deduplicated: if five tasks notify "restart nginx", it restarts once at the end.
- `templates/` — Jinja2 templates rendered with variables at runtime (e.g., systemd unit files with the service user injected).
- `defaults/` — lowest-precedence variable values. Any group_var/host_var overrides these.

Why separate `handlers/`? Imagine you change four lines in `nginx.conf`. Each change notifies "reload nginx". Without deduplication, nginx restarts four times. Handlers collect all notifies and run each once, at the end of the play.

### provision.yml vs deploy.yml

- **`provision.yml`** — installs system packages, creates database users, configures firewalls. Run this once when a VM is fresh or rebuilt. Idempotent, but slow.
- **`deploy.yml`** — syncs your code, rebuilds binaries, restarts services. Run this every time you push new code. Fast.

Rule of thumb: if it involves `apt install`, it belongs in provision. If it involves `git pull` or `go build`, it belongs in deploy.

### Idempotency explained

Idempotent = running it twice is the same as running it once. Ansible modules are designed this way:

- `apt: name=nginx state=present` — installs nginx if not installed. Second run: no-op.
- `copy: src=config.yml dest=/etc/app/config.yml` — copies the file if the destination differs. Second run: no-op because checksum matches.
- `systemd: name=cognitor-proxy state=started` — starts the service if not running. Second run: no-op.

This is why you can re-run a playbook safely. If half the VMs are already configured, the play skips them and fixes the rest. Contrast with shell scripts, where "I already ran this" means "figure out what to delete before re-running."

### What happens when you run `ansible-playbook deploy.yml`

1. **Ansible reads the inventory** to build the host list.
2. **Ansible SSHes into each host** in parallel (up to the fork limit).
3. **Gathers facts** about each host (OS, CPU, IPs, etc.) — available as `ansible_*` variables.
4. **Runs each role's tasks** in order. For each task:
   - Sends a small Python snippet over SSH.
   - Executes it on the remote.
   - Collects the result (changed/ok/failed).
5. **Triggers handlers** at the end of each play for any notified handlers (restart services, reload nginx).
6. **Reports** a per-host summary: how many tasks ok, changed, failed.

If anything fails mid-play, Ansible stops for that host but continues for others. The play is not transactional — partial application is possible. That's why `--check` mode (dry run) and `--diff` are your friends.

---

## 4. Systemd Explained

Every long-running process on our VMs is managed by systemd. systemd is what starts your service on boot, restarts it if it crashes, and gives you logs.

### Unit file anatomy

```ini
[Unit]
Description=Cognitor Proxy Service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=cognitor-proxy
EnvironmentFile=/etc/cognitor/proxy.env
ExecStart=/opt/cognitor/proxy/proxy
Restart=on-failure
RestartSec=5
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
```

- **`[Unit]`** — metadata and ordering. `After=network-online.target` means "don't start me until networking is up". Critical: without this, the proxy might try to dial RabbitMQ before the network is ready, crash, and enter a restart loop.
- **`[Service]`** — how to run the thing. The user, the binary, the environment, the restart policy.
- **`[Install]`** — when to start on boot. `WantedBy=multi-user.target` means "start when the system reaches normal multi-user mode" (i.e., always, on every boot).

### Why `Restart=on-failure` not `always`

- `always` — restart no matter why the process exited, including `systemctl stop`.
- `on-failure` — restart only if the process exited with a non-zero status or was killed by a signal.

With `always`, running `systemctl stop cognitor-proxy` would start a fight — systemd stops the process, then immediately restarts it. You'd have to `systemctl disable --now` to actually stop it. That's surprising, and surprises cause outages during incident response.

`on-failure` is the right default: crashes restart, operators control lifecycle.

### Why `EnvironmentFile` instead of hardcoding secrets

Putting `DATABASE_PASSWORD=hunter2` directly in the unit file means:
1. Anyone who can read the unit file (world-readable by default) sees the password.
2. The unit file lives in git (via Ansible templates), so the password lives in git.

`EnvironmentFile=/etc/cognitor/proxy.env` reads secrets from a file that is:
- Owned by the service user (`cognitor-proxy`).
- Mode `0640` (owner read/write, group read, world no access).
- Written by Ansible at deploy time from values held outside git.

The unit file itself contains no secrets and can be safely committed.

### `NoNewPrivileges=true`

Prevents the process (and any child it spawns) from gaining new privileges via setuid binaries. If an attacker gets code execution inside the proxy, they cannot run `sudo`, cannot escalate via a setuid helper, cannot become root.

Free security win. Zero downside for a Go HTTP server that doesn't need to escalate.

### `PrivateTmp=true`

Gives the service its own private `/tmp` and `/var/tmp`, invisible to other processes. Prevents a common attack class: malicious process drops a file in `/tmp`, waits for target service to read it.

Also prevents tmp-file leaks from polluting the host's shared `/tmp`.

### Service users with `/usr/sbin/nologin`

Services run as unprivileged users (`cognitor-proxy`, `cognitor-history`). These users have:
- No home directory (or a minimal one).
- Shell set to `/usr/sbin/nologin`.

If someone tries `su - cognitor-proxy`, it refuses. The account exists only to own the process. You cannot SSH in as it. You cannot `sudo -u cognitor-proxy bash`. It's a namespace, not a login.

### Debug commands

```bash
# Live log stream (Ctrl+C to exit)
sudo journalctl -u cognitor-proxy -f

# Last hour of logs
sudo journalctl -u cognitor-proxy --since "1 hour ago"

# Current status (running? failed? when restarted?)
sudo systemctl status cognitor-proxy

# Restart the service
sudo systemctl restart cognitor-proxy

# Show me the unit file
sudo systemctl cat cognitor-proxy
```

When a service misbehaves, `journalctl -u <name> -f` then restart the service in another terminal. You see the exact boot sequence and any error.

---

## 5. Message Queue Fundamentals

The proxy publishes to RabbitMQ, the consumer reads from RabbitMQ. Neither talks directly to the other.

### Why a queue between proxy and database?

- **Decoupling.** The proxy does not need to know PostgreSQL exists. It publishes a message and moves on. If PostgreSQL is down, the proxy doesn't care (and doesn't block).
- **Durability.** If the consumer crashes, messages wait in the queue. When the consumer restarts, it resumes where it left off.
- **Back-pressure absorption.** Proxy traffic bursts (say, 100 requests in one second) don't hammer the database. The queue absorbs the burst; the consumer drains it at its own pace.

### Durable queue + persistent messages

- **Durable queue** — the queue definition survives a RabbitMQ restart. Without this, restarting RabbitMQ would delete the queue.
- **Persistent messages** (`delivery_mode=2`) — individual messages are written to disk. Without this, a RabbitMQ restart mid-traffic would drop the in-flight messages still in memory.

Both flags are needed. Durable queue + transient messages = queue survives but messages don't. Transient queue + persistent messages = messages have nowhere to live after restart.

### `basic_qos(prefetch_count=1)`

Without this: RabbitMQ pushes *all* unacknowledged messages to the consumer at once. The consumer buffers them in memory and processes sequentially.

**What goes wrong:** say the queue has 10,000 messages. The consumer starts, RabbitMQ shoves all 10,000 at it. The consumer starts processing #1. The consumer crashes.

RabbitMQ redelivers *all 10,000* on reconnect because none were acknowledged. But worse: the consumer had 10,000 messages in memory — OOM risk.

With `prefetch_count=1`: consumer gets one message, processes it, acks, gets the next. Crash at any point loses at most one in-flight message (which is requeued).

### Ack-after-commit pattern

The consumer's inner loop is roughly:

```python
def on_message(channel, method, properties, body):
    try:
        data = json.loads(body)
        cursor.execute("INSERT ... ON CONFLICT DO NOTHING", data)
        db.commit()                                       # (1)
        channel.basic_ack(delivery_tag=method.delivery_tag)  # (2)
    except Exception:
        db.rollback()
        channel.basic_nack(delivery_tag=method.delivery_tag, requeue=True)
```

**The order matters.** Commit first, ack second. Walk through the crash scenarios:

- **Crash between message receive and step (1) commit:** database is untouched, message is unacked → RabbitMQ redelivers on reconnect. ✓
- **Crash between step (1) and step (2):** row is in the database, but ack never sent → RabbitMQ redelivers. Consumer retries the INSERT. `ON CONFLICT DO NOTHING` silently discards the duplicate. ✓
- **Crash after step (2):** row is in the database, ack is sent, message is gone. ✓

The opposite order (ack before commit) has a fatal scenario: ack goes through, then commit fails → message is gone, row is not written → data loss.

### `ON CONFLICT DO NOTHING` as the safety net

The `UNIQUE (slug, fetched_at)` constraint guarantees that a retry can never create a duplicate row. The consumer doesn't need to track "did I already process this message?" — the database enforces idempotency.

This is the pattern: **exactly-once delivery doesn't exist; at-least-once + idempotent writes is the achievable equivalent.**

### Message type routing (one queue, two shapes)

Today the `market_events` queue carries two message shapes:

- **Market snapshot** — no `type` field. Goes to `market_snapshots` table.
- **Price event** — `type: "price"`. Goes to `price_snapshots` table.

The consumer checks `msg.get("type")` and routes accordingly. Why not two queues? Simpler infra: one queue, one consumer, one connection, one set of acks. The routing logic is five lines of Python.

**Backwards compatibility:** existing market messages have no `type` field, and the router treats missing type as "market". Deploying the price feature did not require draining the queue or coordinating a version bump.

---

## 6. Database Decisions

### `TIMESTAMPTZ` vs `TIMESTAMP`

`TIMESTAMPTZ` stores the instant in UTC and converts on read based on session timezone. `TIMESTAMP` stores wall-clock time with no timezone info.

**Concrete corruption scenario with naive TIMESTAMP:**
1. Consumer runs on node-01 (UTC). Inserts `2026-04-03 14:00:00`.
2. You migrate PostgreSQL to a host with `America/New_York` locale.
3. An API client reads the row and interprets `14:00:00` as 2pm Eastern = 18:00 UTC.
4. The chart X-axis is now four hours off. Nobody notices for a week.

`TIMESTAMPTZ` prevents this: the database always knows what instant the row represents, regardless of which machine reads it.

### `UNIQUE` constraints for idempotent writes

`UNIQUE (slug, fetched_at)` says: "only one market_snapshots row can exist per (slug, time) pair."

Combined with `ON CONFLICT DO NOTHING` in the INSERT, retries become safe. The consumer can process the same message 1 time or 100 times and the database ends up in the same state.

Without this constraint, a crash-retry cycle during a backlog replay would create thousands of duplicate rows. Your charts would double-count. Your row counts would lie.

### Indexes on `(slug, fetched_at DESC)`

The History API's hot query is:

```sql
SELECT * FROM market_snapshots
WHERE slug = $1
ORDER BY fetched_at DESC
LIMIT 100;
```

**Without the index:** PostgreSQL scans every row in the table, filters by slug, sorts, returns 100. At 1,000 rows: fast. At 100,000 rows: slow. At 10,000,000 rows: timeouts.

**With `(slug, fetched_at DESC)`:** PostgreSQL jumps straight to the slug, walks 100 entries, done. Constant time regardless of table size.

The `DESC` in the index matches the query's sort order — PostgreSQL can walk the index in reverse and skip the sort step entirely.

### Consumer owns schema (CREATE TABLE IF NOT EXISTS on startup)

Two services touch PostgreSQL: the consumer (writes) and the history API (reads). Only the consumer runs `CREATE TABLE IF NOT EXISTS` on startup.

Why not the API? The API might start first, create tables, then the consumer starts and tries to also create them — conflict. Or someone changes the schema and the API is redeployed first with an old idea of the schema. Then the consumer restarts with new columns the API doesn't know about.

**Rule: one service owns schema.** Everyone else assumes it exists. When schema changes, you deploy the owner first. This gives you a single bottleneck for migrations — which is what you want.

---

## 7. Caching Strategy

Three cache layers, each with a distinct job.

| Layer | Used for | TTL | Survives restart? |
|-------|----------|-----|-------------------|
| Go RAM cache | `/whales` (5 min), `/prices` (60s) | bounded by refresh ticker | no |
| Redis | session state (`/state`) | 24h | yes |
| PostgreSQL | market + price history | forever | yes |

### When to use each layer

- **Go RAM cache** — data you can re-fetch cheaply, acceptable staleness, one proxy instance.
- **Redis** — small pieces of state that must survive a process restart but don't need a relational model.
- **PostgreSQL** — time-series data, structured queries, reports, charts.

### Why Go RAM cache for prices and whales

- **Zero network overhead.** It's a `map[string]T` guarded by a mutex. Microsecond-scale reads.
- **Single instance.** We run one proxy. No cache-coherence problem.
- **Acceptable staleness.** Whale positions don't move second-to-second. Prices change, but a 60-second window is fine for a dashboard.
- **Simple invalidation.** The background ticker just overwrites the cache. No cache-invalidation gymnastics.

If we scaled to two proxy instances, the RAM cache would fragment — each instance would have its own view. That's when you'd move these caches to Redis (shared between instances).

### Why Redis for session state

- **Must survive process restart.** If you redeploy the proxy, users should not lose their active tab / scroll position. Go RAM cache evaporates on restart.
- **Key-value with TTL is a perfect fit.** Key = `session:<uuid>`, value = JSON, TTL = 24h. Redis was literally built for this.
- **Small data.** Each session is a few hundred bytes. Redis is cheap.

### Why not Redis for everything

- **Network hop.** Every Redis call is an RPC, even if it's localhost. Compared to a mutex-guarded map, it's ~1000x slower.
- **Operational overhead.** Another process to monitor, back up, secure.
- **Simpler is better when you have one instance.** If your whole app fits on one VM and you don't need persistence for a piece of data, RAM is the right answer.

The rule: **start with RAM, escalate to Redis only when RAM can't meet a specific requirement** (survival, sharing, size).

---

## 8. Security Basics

### SSH keys over passwords

Passwords are guessable. A 2048-bit SSH key has ~600 digits of entropy. Brute-forcing it would outlast the universe.

Passwords also get reused across systems; keys don't. A compromised key reveals only the compromised machine.

### UFW default-deny

UFW's policy is "deny incoming by default, allow what you explicitly list." This is the opposite of "allow everything, block the known-bad."

Default-deny means: if you forget to write a firewall rule, the service is *unreachable*, not *unprotected*. The failure mode is "it doesn't work" — noisy, fixable. The opposite failure mode is "it's wide open" — silent, catastrophic.

### NoNewPrivileges

Prevents privilege escalation via setuid binaries. If a bug gives an attacker code execution inside the proxy, they cannot run `sudo`, cannot exploit a setuid helper to become root.

### PrivateTmp

Isolates the service's temp files from the shared `/tmp`. Prevents:
- Info leakage (service drops secrets in /tmp, another process reads them).
- Symlink attacks (attacker places a symlink in /tmp, service follows it into sensitive paths).

### Service users with no login shell

Every service runs as its own unprivileged user with `/usr/sbin/nologin`. This means:
- You cannot SSH in as `cognitor-proxy`.
- You cannot `su - cognitor-proxy`.
- If the process is compromised, the attacker is stuck in a user account with no home, no shell, no sudo.

### secrets.yml gitignored

Passwords never enter git history. This matters because:
- Git history is forever. A password committed once lives in every clone, forever.
- Public repos leak credentials constantly — entire ecosystems exist around scraping GitHub for leaked keys.
- `.gitignore` + `.example` template is the standard discipline: structure in git, values out of git.

### EnvironmentFile at runtime

systemd reads `/etc/cognitor/proxy.env` at service start. The file is mode `0640`, owned by the service user. Secrets are in exactly one place on disk (not in the unit file, not in the binary, not in logs).

### Redis localhost-only

Session state includes things like active tab and scroll position — not sensitive. But Redis has no authentication by default. Binding to 127.0.0.1 means: no network path exists to reach it. Even if someone lands on the VM, they still need to be inside the proxy process to talk to Redis.

Depth matters. No single layer is sufficient; together they make exploitation expensive.

---

## 9. Failure Modes

What happens when each component fails. Specifics matter — "it breaks" is not an answer.

### RabbitMQ down

- **Proxy on startup:** dials RabbitMQ, fails, retries with backoff. Does not crash the process.
- **Proxy at runtime:** `/current`, `/whales`, `/prices`, `/state` all still return data (live data comes from external APIs or Redis, not from RabbitMQ).
- **Publish calls:** fail, logged as errors.
- **Messages:** *lost* for the duration of the outage. Nothing queues them because RabbitMQ is the queue. When RabbitMQ recovers, the proxy resumes publishing new snapshots. Old snapshots that were never published are gone.

**Honest tradeoff:** We do not implement a local write-ahead log in the proxy. For this dashboard, missing 15 minutes of snapshot history is acceptable. For a payments system, it would not be.

### PostgreSQL down

- **Consumer:** INSERT fails → rollback → nack with requeue → message goes back to queue.
- **Messages:** accumulate in RabbitMQ. Queue depth grows. When PostgreSQL recovers, consumer drains the backlog.
- **History API:** returns 500 on every request. UI's History tab shows an error.
- **Proxy:** unaffected — it never talks to PostgreSQL.

Graceful degradation: Live Markets tab works, History tab doesn't.

### CoinGecko / NBU down

- **Proxy background fetcher:** request fails, logs warning, leaves existing cache in place.
- **`/prices` endpoint:** returns stale cache (up to the age of the last successful fetch).
- **UI ticker:** shows last known prices. Clock keeps ticking on the frontend; server-side timestamps do not update.

Stale data is better than no data here. The UI does not know it's stale unless we add "last updated" UI (nice-to-have).

### Redis down

- **Proxy:** all endpoints except `/state` work normally.
- **`/state` GET/POST:** returns 503.
- **UI:** tab and scroll position are not persisted. User reloads → defaults.

Session state is a nice-to-have. Losing it is annoying, not fatal.

### Node-02 (proxy VM) down

- **UI:** `/current`, `/whales`, `/prices`, `/state` all fail. Live Markets tab is empty.
- **History tab:** still works (talks to node-01 directly).
- **Consumer on node-01:** nothing to consume (no new messages being published), sits idle.

### Node-01 (database + queue) down

- **Consumer:** down (same VM).
- **History API:** down (same VM).
- **RabbitMQ:** down (same VM) → proxy publishes fail, messages lost until recovery.
- **Live Markets tab:** still works! Proxy's `/current` and `/whales` fetch from external APIs, return to the browser, only the *publish* fails. User sees data.

### Node-03 (UI VM) down

- **Users:** cannot load the dashboard.
- **Backend:** completely unaffected. Data ingestion continues.

---

## 10. Operational Runbook

Concrete commands for common operational tasks. Keep these handy.

```bash
# ---- Check service health ----
ssh vagrant@172.31.1.11 sudo systemctl status cognitor-proxy
ssh vagrant@172.31.1.10 sudo systemctl status cognitor-history-consumer
ssh vagrant@172.31.1.10 sudo systemctl status cognitor-history-api

# ---- Follow logs ----
ssh vagrant@172.31.1.11 sudo journalctl -u cognitor-proxy -f
ssh vagrant@172.31.1.10 sudo journalctl -u cognitor-history-consumer --since "1 hour ago"
ssh vagrant@172.31.1.10 sudo journalctl -u cognitor-history-api -f

# ---- Verify API endpoints ----
curl http://172.31.1.11:8080/health
curl http://172.31.1.11:8080/prices
curl http://172.31.1.10:8000/health
curl "http://172.31.1.10:8000/prices/history/bitcoin?limit=5"

# ---- Queue depth (how many unprocessed messages?) ----
ssh vagrant@172.31.1.10 sudo rabbitmqctl list_queues name messages consumers

# ---- Database row counts ----
ssh vagrant@172.31.1.10 'sudo -u postgres psql cognitor -c "SELECT count(*) FROM market_snapshots; SELECT count(*) FROM price_snapshots;"'

# ---- Redis session count ----
ssh vagrant@172.31.1.11 redis-cli KEYS "session:*" | wc -l

# ---- UFW status ----
ssh vagrant@172.31.1.10 sudo ufw status
ssh vagrant@172.31.1.11 sudo ufw status
ssh vagrant@172.31.1.12 sudo ufw status

# ---- Redeploy after code changes ----
git push
ansible-playbook -i ansible/inventory ansible/deploy.yml

# ---- Reprovision one VM from scratch ----
ansible-playbook -i ansible/inventory ansible/provision.yml --limit softserve-node-02
ansible-playbook -i ansible/inventory ansible/deploy.yml --limit softserve-node-02

# ---- Restart a single service ----
ssh vagrant@172.31.1.11 sudo systemctl restart cognitor-proxy

# ---- Peek at in-flight env for a service ----
ssh vagrant@172.31.1.11 sudo systemctl show cognitor-proxy -p Environment

# ---- Manual one-off DB query ----
ssh vagrant@172.31.1.10 'sudo -u postgres psql cognitor -c "SELECT coin, count(*) FROM price_snapshots GROUP BY coin;"'
```

### Investigation order when something's broken

1. **Is the service running?** `systemctl status`. If not, check logs for crash reason.
2. **Are its dependencies reachable?** Proxy: Gamma API, CoinGecko, RabbitMQ, Redis. Consumer: RabbitMQ, PostgreSQL. API: PostgreSQL.
3. **What do the logs say in the last 5 minutes?** `journalctl -u <svc> --since "5 min ago"`.
4. **Is there a queue backlog?** `rabbitmqctl list_queues`. Growing queue = consumer is broken or slow.
5. **Can you reach the endpoint manually?** `curl` from the same VM, then from another VM, then from outside. Failure between steps 2 and 3 = firewall issue.

The goal is to narrow the failure domain with each step. Don't guess — check.

---

## Closing thought

Every pattern here — the queue, the caches, the security flags, the idempotent writes — exists because someone got burned by its absence. You don't have to get burned to learn them, but you do have to *understand* them, or you'll skip them on the next system you build and discover the hard way why they existed.

Read the `architecture.md` and `deployment.md` alongside this guide. Architecture says *what*. Deployment says *how*. This guide says *why*.
