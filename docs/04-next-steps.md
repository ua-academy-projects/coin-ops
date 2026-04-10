# Next Steps

## 1. Understand Docker Properly

Deep dive into core concepts before moving further:

- How Docker builds images layer by layer and why order in Dockerfile matters
- How layer caching works — when cache is reused vs invalidated
- How Docker networking works internally — bridge networks, DNS resolution
- Difference between image layers and container layers
- How volumes work — bind mounts vs named volumes

## 2. Understand Docker Compose Properly

- How `depends_on` and `healthcheck` work together
- How Docker resolves container names on the internal network
- Difference between `build` and `image` in docker-compose.yml
- What `restart` policies do and when to use them
- How environment variables are passed to containers

## 3. Reduce Image Sizes with Alpine

Current images use `slim` (minimal Debian). Alpine is even smaller:

| Current | Size | Alpine alternative | Size |
|---|---|---|---|
| `python:3.10-slim` | ~185MB | `python:3.10-alpine` | ~50MB |
| `debian:bookworm-slim` | ~116MB | `alpine:3.19` | ~7MB |

**Note:** Alpine uses `musl` instead of `glibc`. Some Python packages (like `psycopg2`) need extra build steps on Alpine. Test carefully before switching.

## 4. Remove All Hardcoded Values

Currently passwords and IPs are hardcoded directly in source files and docker-compose.yml. This is bad practice — credentials should never be pushed to GitHub.

**Solution — environment variables + .env file:**

```yaml
# docker-compose.yml — use variables instead of plain values
services:
  rabbitmq:
    environment:
      RABBITMQ_DEFAULT_USER: ${RABBITMQ_USER}
      RABBITMQ_DEFAULT_PASS: ${RABBITMQ_PASS}
```

```bash
# .env file — actual values, never committed to git
RABBITMQ_USER=proxy_user
RABBITMQ_PASS=proxy_password
POSTGRES_HOST=192.168.56.105
POSTGRES_PASS=history_password
```

```bash
# .gitignore — make sure .env is excluded
.env
```

Docker Compose automatically reads `.env` file from the same directory.

## 5. Clean Up Unused Docker Images

```bash
# Remove all unused images, stopped containers, build cache
docker system prune -a

# Remove only untagged (dangling) images
docker image prune

# Remove images not used by any running container
docker image prune -a

# Remove specific image by name
docker rmi image_name:tag

# List all images with sizes
docker images

# List images sorted to find largest
docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}"
```
