# Feature — Redis Cache

## What Changed

Replaced the in-memory Python variable cache with Redis.

## Why

**Before (in-memory cache):**
```python
_cache = {"data": None, "timestamp": 0}
```
This variable lives in RAM inside the Python process. If `proxy-service` restarts for any reason — cache is lost, next request hits CoinGecko API immediately.

**After (Redis):**
Redis is a separate service that stores data outside the Python process. Proxy restart → Redis keeps the cache → no unnecessary API calls.

## What Redis Does

- Stores the last fetched rates as JSON
- Sets a 25-second TTL (Time To Live) — data auto-expires, no manual timestamp checking
- Survives proxy service restarts
- Runs on the same VM as the proxy (server2)

## Installation on server2

```bash
sudo apt update && sudo apt install -y redis-server
sudo systemctl status redis   # verify running on 127.0.0.1:6379
pip install redis
```

## Code Change in proxy app.py

```python
# Before
_cache = {"data": None, "timestamp": 0}

# After
import redis
r = redis.Redis(host="127.0.0.1", port=6379, db=0)

# Store with TTL — auto-expires after 25 seconds
r.setex("rates_cache", CACHE_TTL, json.dumps(data))

# Read from cache
cached = r.get("rates_cache")
if cached:
    return jsonify(json.loads(cached))
```

## Verify Redis Is Working

```bash
redis-cli get rates_cache   # shows cached JSON data
```

## Note for Docker

When running in Docker Compose, Redis host changes from `127.0.0.1` to `redis` (container name):
```python
r = redis.Redis(host="redis", port=6379, db=0)
```
