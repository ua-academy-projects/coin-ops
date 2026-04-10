# Iteration 2 — Docker Compose

## What Changed

Services moved from individual VMs to Docker containers running on server1.
PostgreSQL stays on server5 VM — databases should not run in disposable containers.

## Why Docker

- Manual VM setup is not reproducible — different OS versions break things
- Docker packages exact Python/Go versions + dependencies into one image
- Same image runs identically on any machine
- Container names replace IPs — no more manual IP management

## Container Architecture

```
server1 (Docker host)
  ├── container: ui       — React + Flask (port 8080)
  ├── container: proxy    — Flask + Redis cache (port 5000)
  ├── container: rabbitmq — Message queue (port 5672)
  ├── container: redis    — Cache for proxy
  └── container: history  — Go consumer service
server5 (VM) — PostgreSQL stays here
```

## Key Concepts

**Dockerfile** — recipe for building an image (step-by-step instructions)
**Image** — the built result, a frozen ready-to-run package
**Container** — a running instance of that image
**Layer caching** — each Dockerfile line is cached; if only code changes, dependencies are not reinstalled

## Multi-Stage Builds

Used for UI (Node → Python) and History (Go → Debian):
- Stage 1: heavy build image compiles/builds the app
- Stage 2: tiny runtime image copies only the result
- Final image does NOT include Node.js or Go — much smaller

## RabbitMQ Users via definitions.json

Docker RabbitMQ image only supports ONE default user via environment variables.
To add history_user, use a definitions file loaded at startup — no scripts needed:

```json
{
  "users": [
    {"name": "proxy_user", "password": "proxy_password", "tags": "administrator"},
    {"name": "history_user", "password": "history_password", "tags": ""}
  ],
  "permissions": [
    {"user": "proxy_user", "vhost": "/", "configure": ".*", "write": ".*", "read": ""},
    {"user": "history_user", "vhost": "/", "configure": ".*", "write": "", "read": ".*"}
  ],
  "vhosts": [{"name": "/"}]
}
```

## How to Run

```bash
cd docker/
docker compose up --build   # first time — builds all images
docker compose up           # subsequent runs — reuse cached images
docker compose down         # stop everything
docker ps                   # check running containers
docker logs history         # view specific service logs
```

## Mistakes & Fixes

| Mistake | Cause | Fix |
|---|---|---|
| `golang:1.21-slim` not found | Go has no slim variant for 1.21 | Use `golang:1.21` full image |
| `go.mod requires go >= 1.22.2` | Dockerfile used Go 1.21, code needs 1.22 | Changed to `golang:1.22` |
| Connection reset during download | Network dropped mid-download of 600MB Go image | Retry — Docker resumes from cached layers |
| No space left on device | Docker images filled 11.5GB logical volume | Extended LVM: `lvextend` + `resize2fs` |
| `COPY ui_service/requirements.txt` not found | Dockerfile path didn't match folder name | Fixed path in Dockerfile |
| Port 8080 already in use | Old systemd ui-service still running | `sudo systemctl stop ui-service` |
| `ContainerConfig` KeyError | Old docker-compose v1.29 incompatible with Docker 29 | Installed Docker Compose v2 plugin |
| Network incorrect label | v1 created network, v2 expects different metadata | `docker network rm coinops-network` |
| `history_user` invalid credentials | RabbitMQ Docker only creates one default user | Switched to definitions.json approach |
| `curl: command not found` in setup container | RabbitMQ image has no curl | Dropped setup container, used definitions.json |

## Files

```
docker/
├── docker-compose.yml
└── rabbitmq/
    └── definitions.json
proxy_service/
├── app.py
├── Dockerfile
└── requirements.txt
ui_service/
├── app.py
├── Dockerfile
└── requirements.txt
history_service/
├── main.go
├── Dockerfile
├── go.mod
└── go.sum
```
