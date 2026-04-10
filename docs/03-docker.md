# Iteration 2 — Docker Compose

## What Changed

Services moved from individual VMs to Docker containers running on server1.
PostgreSQL stays on server5 VM — databases should not run in disposable containers.

## Why Docker

Manual VM setup has a fundamental problem: it is not reproducible. Each VM was configured by hand — specific OS version, packages installed in a specific order, paths hardcoded. If you set up a new VM, or a teammate does it on their machine, something breaks because the environment is slightly different.

Docker solves this by packaging everything the app needs into one image:

- Exact Python/Go version locked in Dockerfile
- Exact package versions locked in requirements.txt / go.mod
- Same image runs identically on any machine, any OS
- Container names replace IPs — no more manual IP management when network changes

---

## Core Concepts

**Dockerfile** — a text file with step-by-step instructions for building an image. Docker reads it top to bottom, each line creates a layer.

**Image** — the built result of following those instructions. A frozen, ready-to-run package. Like a ZIP file containing everything the app needs. One image can run as many containers as needed.

**Container** — a running instance of an image. The app is actually alive and working.

**Layer caching** — Docker caches each layer. If only `app.py` changes, Docker reuses all previous layers (OS, packages). Only the changed layer rebuilds. This makes subsequent builds much faster.

### Key Dockerfile Instructions

| Instruction | Purpose |
|---|---|
| `FROM` | Base image to start from |
| `WORKDIR` | Set working directory inside container |
| `COPY` | Copy files from host into image |
| `RUN` | Execute command during build |
| `EXPOSE` | Document which port the app uses |
| `CMD` | Command to run when container starts |

---

## Multi-Stage Builds

Used for UI service (Node → Python) and History service (Go → Debian).

**Why:** Build tools are heavy. Node.js is ~400MB, Go compiler is ~600MB. The final running app doesn't need them — only the build output (compiled binary or static files).

**How it works:**
- Stage 1 uses the heavy build image to compile/build
- Stage 2 copies only the result into a tiny runtime image
- Final image does NOT include Node.js or Go

**Result:** UI image is ~120MB instead of ~500MB. History image is ~30MB instead of ~700MB.

```dockerfile
# History service — multi-stage example
FROM golang:1.22 AS builder      # Stage 1: compile
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY main.go .
RUN CGO_ENABLED=0 GOOS=linux go build -o history_service .

FROM debian:bookworm-slim        # Stage 2: just run the binary
WORKDIR /app
COPY --from=builder /app/history_service .
CMD ["./history_service"]
```

`CGO_ENABLED=0` makes the binary fully static — runs on any Linux without extra libraries.

---

## Container Architecture

```
server1 (Docker host)
  ├── container: ui        — React + Flask (port 8080)
  ├── container: proxy     — Flask + Redis cache (port 5000)
  ├── container: rabbitmq  — Message queue (ports 5672, 15672)
  ├── container: redis     — Cache for proxy service
  └── container: history   — Go consumer service
server5 (VM, unchanged) — PostgreSQL database
```

All containers share one Docker network (`coinops-network`). They communicate by **container name**, not IP address. Docker resolves names internally.

**Before (bare VM):**
```python
RABBITMQ_HOST = "192.168.56.103"  # breaks when IP changes
r = redis.Redis(host="127.0.0.1")  # wrong inside container
```

**After (Docker Compose):**
```python
RABBITMQ_HOST = "rabbitmq"   # Docker resolves this
r = redis.Redis(host="redis") # Docker resolves this
```

---

## RabbitMQ Users — definitions.json

Docker RabbitMQ image only supports **one** default user via environment variables (`RABBITMQ_DEFAULT_USER`). We need two users with different permissions.

**Failed approaches:**
1. Separate `rabbitmq-setup` container running `rabbitmqctl` — failed because Erlang cookie mismatch between containers
2. Setup script using `curl` — failed because RabbitMQ image has no `curl`

**Working solution:** RabbitMQ's built-in definitions file loaded at startup. No scripts, no extra containers.

```json
{
  "users": [
    {"name": "proxy_user",   "password": "proxy_password",   "tags": "administrator"},
    {"name": "history_user", "password": "history_password", "tags": ""}
  ],
  "permissions": [
    {"user": "proxy_user",   "vhost": "/", "configure": ".*", "write": ".*", "read": ""},
    {"user": "history_user", "vhost": "/", "configure": ".*", "write": "",   "read": ".*"}
  ],
  "vhosts": [{"name": "/"}]
}
```

Loaded via environment variable in docker-compose.yml:
```yaml
environment:
  RABBITMQ_SERVER_ADDITIONAL_ERL_ARGS: -rabbitmq_management load_definitions "/etc/rabbitmq/definitions.json"
volumes:
  - ./rabbitmq/definitions.json:/etc/rabbitmq/definitions.json
```

---

## docker-compose.yml — Key Concepts

```yaml
depends_on:
  rabbitmq:
    condition: service_healthy   # wait until healthcheck passes, not just started
```

```yaml
healthcheck:
  test: ["CMD", "rabbitmq-diagnostics", "ping"]
  interval: 10s
  retries: 5
```

```yaml
restart: on-failure   # restart container automatically if it crashes
```

**Why `restart: on-failure` on history service:** Go service exits immediately if RabbitMQ connection is refused. Even with `depends_on: service_healthy`, there is a small window where RabbitMQ is up but not yet accepting connections. Restart policy handles this gracefully.

---

## How to Run

```bash
# First time — build all images and start
cd docker/
docker compose up --build

# Subsequent runs — reuse cached images
docker compose up

# Run in background
docker compose up -d

# Stop everything
docker compose down

# Check running containers
docker ps

# View logs for specific service
docker logs history
docker logs rabbitmq

# Remove all containers (clean slate)
docker rm -f $(docker ps -aq)

# Free disk space — remove unused images and cache
docker system prune -a
```

---

## Disk Space — LVM Extension

Docker images filled the 11.5GB logical volume. The physical partition (23GB) had free space that Ubuntu wasn't using.

```bash
# Check current state
lsblk
df -h /

# Extend logical volume to use all available free space
sudo lvextend -l +100%FREE /dev/ubuntu-vg/ubuntu-lv

# Resize filesystem to use new space (online, no reboot needed)
sudo resize2fs /dev/mapper/ubuntu--vg-ubuntu--lv

# Verify
df -h /   # should show 23GB now
```

---

## Installing Docker Compose v2

Ubuntu ships `docker-compose` v1.29 which is incompatible with Docker 29. Must install v2 plugin manually:

```bash
sudo mkdir -p /usr/local/lib/docker/cli-plugins
sudo curl -SL https://github.com/docker/compose/releases/download/v2.24.0/docker-compose-linux-x86_64 \
  -o /usr/local/lib/docker/cli-plugins/docker-compose
sudo chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
docker compose version   # verify: Docker Compose version v2.24.0
```

**Important:** Use `docker compose` (space, v2) not `docker-compose` (hyphen, v1).

---

## Mistakes & Fixes

| # | Mistake | Cause | Fix |
|---|---|---|---|
| 1 | `golang:1.21-slim` not found | Go has no slim variant for 1.21 | Use `golang:1.21` full image — final image is still small due to multi-stage build |
| 2 | `go.mod requires go >= 1.22.2` | Dockerfile used Go 1.21 but code requires 1.22 | Always check `go.mod` for required Go version before writing Dockerfile |
| 3 | Connection reset during download | Network dropped mid-download of 600MB Go image | Retry — Docker resumes from cached layers automatically |
| 4 | No space left on device | Docker images filled 11.5GB logical volume | Extended LVM partition to use existing free space on 23GB disk |
| 5 | `COPY ui_service/requirements.txt` not found | Dockerfile referenced wrong path — folder is `ui/` not `ui_service/` | Fixed path in Dockerfile with `sed` |
| 6 | Port 8080 already in use | Old systemd `ui-service` still running alongside Docker container | `sudo systemctl stop ui-service` — one process per port |
| 7 | `ContainerConfig` KeyError | `docker-compose` v1.29 incompatible with Docker 29 when recreating containers | Install Docker Compose v2 plugin, use `docker compose` |
| 8 | Network incorrect label | v1 created network with different metadata, v2 rejects it | `docker network rm coinops-network` — v2 recreates correctly |
| 9 | `history_user` invalid credentials | RabbitMQ Docker creates only one user from env vars | Switched to `definitions.json` — loads all users at startup |
| 10 | `curl: command not found` in setup container | RabbitMQ image has no curl installed | Dropped setup container entirely, used definitions.json instead |

---

## File Structure

```
docker/
├── docker-compose.yml
└── rabbitmq/
    └── definitions.json

proxy_service/
├── app.py            ← uses "rabbitmq" and "redis" as hostnames
├── Dockerfile
└── requirements.txt

ui_service/
├── app.py            ← static_folder points to /app/dist inside container
├── Dockerfile        ← multi-stage: Node builds React, Python serves it
└── requirements.txt

history_service/
├── main.go           ← uses "rabbitmq" hostname, PostgreSQL IP stays
├── Dockerfile        ← multi-stage: Go compiles binary, Debian runs it
├── go.mod
└── go.sum
```
