"""
Optional Redis-backed UI state.

When ``REDIS_URL`` is unset or Redis is unreachable, the API reports ``enabled: false``
and the browser keeps using ``localStorage`` only.

After a connection failure the module retries after ``_RETRY_INTERVAL_S`` seconds
instead of staying down until the process restarts.
"""

from __future__ import annotations

import json
import logging
import os
import time
import uuid
from typing import Any, Optional

LOG = logging.getLogger("coinops.state")

_redis: Any = None
_last_failure: float = 0.0
_RETRY_INTERVAL_S = 60

_KEY_PREFIX_DEFAULT = "coinops:ui:"
_cached_key_prefix: Optional[str] = None
_cached_ttl: Optional[int] = None


def _key_prefix() -> str:
    global _cached_key_prefix
    if _cached_key_prefix is None:
        raw = os.environ.get("COINOPS_REDIS_KEY_PREFIX", _KEY_PREFIX_DEFAULT).strip()
        _cached_key_prefix = raw or _KEY_PREFIX_DEFAULT
    return _cached_key_prefix


def _ttl_seconds() -> int:
    global _cached_ttl
    if _cached_ttl is None:
        raw = int(os.environ.get("COINOPS_UI_STATE_TTL_SECONDS", str(60 * 60 * 24 * 365)))
        _cached_ttl = max(raw, 60)
    return _cached_ttl


def get_redis():
    """Return a redis client or ``None`` if Redis is not configured / unavailable."""
    global _redis, _last_failure

    if _redis is not None:
        return _redis

    if _last_failure and (time.monotonic() - _last_failure) < _RETRY_INTERVAL_S:
        return None

    url = os.environ.get("REDIS_URL", "").strip()
    if not url:
        _last_failure = time.monotonic()
        return None
    try:
        import redis as redis_mod
        from redis.exceptions import RedisError

        client = redis_mod.from_url(url, decode_responses=True)
        client.ping()
        _redis = client
        _last_failure = 0.0
        return _redis
    except Exception as exc:
        LOG.warning("Redis unavailable: %s", exc)
        _last_failure = time.monotonic()
        return None


def redis_ui_enabled() -> bool:
    return get_redis() is not None


def valid_sid(value: Optional[str]) -> bool:
    if not value or len(value) != 32:
        return False
    try:
        int(value, 16)
    except ValueError:
        return False
    return True


def new_session_id() -> str:
    return uuid.uuid4().hex


def get_ui_state(sid: str) -> dict[str, Any]:
    r = get_redis()
    if not r:
        return {}
    try:
        raw = r.get(f"{_key_prefix()}{sid}")
    except Exception:
        _mark_failed()
        return {}
    if not raw:
        return {}
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        return {}
    return data if isinstance(data, dict) else {}


def set_ui_state(sid: str, state: dict[str, Any]) -> None:
    r = get_redis()
    if not r:
        return
    payload = json.dumps(state, separators=(",", ":"), ensure_ascii=False)
    try:
        r.setex(f"{_key_prefix()}{sid}", _ttl_seconds(), payload)
    except Exception:
        _mark_failed()


def _mark_failed() -> None:
    """Reset cached client so the next call triggers a reconnection attempt."""
    global _redis, _last_failure
    _redis = None
    _last_failure = time.monotonic()
