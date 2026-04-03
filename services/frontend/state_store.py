"""
Optional Redis-backed UI state.

When ``REDIS_URL`` is unset or Redis is unreachable, the API reports ``enabled: false``
and the browser keeps using ``localStorage`` only.
"""

from __future__ import annotations

import json
import logging
import os
import uuid
from typing import Any, Optional

LOG = logging.getLogger("coinops.state")

_redis: Any = None
_redis_failed: bool = False

KEY_PREFIX_DEFAULT = "coinops:ui:"


def _key_prefix() -> str:
    return os.environ.get("COINOPS_REDIS_KEY_PREFIX", KEY_PREFIX_DEFAULT).strip() or KEY_PREFIX_DEFAULT


def get_redis():
    """Return a redis client or ``None`` if Redis is not configured / unavailable."""
    global _redis, _redis_failed
    if _redis is not None:
        return _redis
    if _redis_failed:
        return None
    url = os.environ.get("REDIS_URL", "").strip()
    if not url:
        _redis_failed = True
        return None
    try:
        import redis as redis_mod

        client = redis_mod.from_url(url, decode_responses=True)
        client.ping()
        _redis = client
        return _redis
    except Exception as exc:  # noqa: BLE001 — log and degrade to no-Redis mode
        LOG.warning("Redis unavailable: %s", exc)
        _redis_failed = True
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
    raw = r.get(f"{_key_prefix()}{sid}")
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
    ttl = int(os.environ.get("COINOPS_UI_STATE_TTL_SECONDS", str(60 * 60 * 24 * 365)))
    if ttl < 60:
        ttl = 60
    payload = json.dumps(state, separators=(",", ":"), ensure_ascii=False)
    r.setex(f"{_key_prefix()}{sid}", ttl, payload)
