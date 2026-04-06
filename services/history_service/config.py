"""Configuration for the CoinOps history service."""

from __future__ import annotations

import os
from dataclasses import dataclass
from typing import MutableMapping, Optional
from urllib.parse import unquote, urlparse

# Behavioral defaults (application-level conventions, not secrets/infrastructure).
_DEFAULT_MQ_EXCHANGE = "coinops.rates"
_DEFAULT_MQ_QUEUE = "coinops.history"
_DEFAULT_MQ_ROUTING_KEY = "rates.snapshot"
_DEFAULT_HISTORY_LISTEN = "0.0.0.0"
_DEFAULT_HISTORY_PORT = "8090"
_DEFAULT_MQ_PREFETCH = "10"
_DEFAULT_MQ_BACKOFF_INITIAL = "1.0"
_DEFAULT_MQ_BACKOFF_MAX = "60.0"


@dataclass(frozen=True)
class HistoryConfig:
    """Runtime configuration for MQ consumer + history API."""

    pg_host: str
    pg_port: int
    pg_user: str
    pg_password: str
    pg_database: str
    rabbitmq_url: str
    rabbitmq_exchange: str
    rabbitmq_queue: str
    rabbitmq_routing_key: str
    mq_consumer_enabled: bool
    http_api_enabled: bool
    history_listen: str
    history_port: int
    mq_prefetch_count: int
    mq_backoff_initial: float
    mq_backoff_max: float
    history_cors_allow_origin: str

    @classmethod
    def from_environ(cls, environ: Optional[MutableMapping[str, str]] = None) -> HistoryConfig:
        """Load config from env vars; DATABASE_URL overrides PG* variables."""
        env = environ if environ is not None else os.environ
        db_url = env.get("DATABASE_URL", "").strip()
        if db_url:
            host, port, user, password, database = _parse_database_url(db_url)
        else:
            host = _env_required(env, "PGHOST")
            port = int(_env_required(env, "PGPORT"))
            user = _env_required(env, "PGUSER")
            password = _env_required(env, "PGPASSWORD")
            database = _env_required(env, "PGDATABASE")
        prefetch = _env_positive_int(env.get("MQ_PREFETCH_COUNT"), _DEFAULT_MQ_PREFETCH, upper=500)
        bo_init = _env_positive_float(env.get("MQ_RECONNECT_BACKOFF_INITIAL"), _DEFAULT_MQ_BACKOFF_INITIAL)
        bo_max = _env_positive_float(env.get("MQ_RECONNECT_BACKOFF_MAX"), _DEFAULT_MQ_BACKOFF_MAX)
        if bo_max < bo_init:
            bo_max = bo_init
        cors = (env.get("HISTORY_CORS_ALLOW_ORIGIN") or "").strip()
        return cls(
            pg_host=host,
            pg_port=port,
            pg_user=user,
            pg_password=password,
            pg_database=database,
            rabbitmq_url=_env_required(env, "RABBITMQ_URL"),
            rabbitmq_exchange=env.get("RABBITMQ_EXCHANGE", _DEFAULT_MQ_EXCHANGE),
            rabbitmq_queue=env.get("RABBITMQ_QUEUE", _DEFAULT_MQ_QUEUE),
            rabbitmq_routing_key=env.get("RABBITMQ_ROUTING_KEY", _DEFAULT_MQ_ROUTING_KEY),
            mq_consumer_enabled=_env_bool(env.get("MQ_CONSUMER_ENABLED"), default=True),
            http_api_enabled=_env_bool(env.get("HTTP_API_ENABLED"), default=True),
            history_listen=env.get("HISTORY_LISTEN", _DEFAULT_HISTORY_LISTEN),
            history_port=int(env.get("HISTORY_PORT", _DEFAULT_HISTORY_PORT)),
            mq_prefetch_count=prefetch,
            mq_backoff_initial=bo_init,
            mq_backoff_max=bo_max,
            history_cors_allow_origin=cors,
        )


def _env_required(env: MutableMapping[str, str], key: str) -> str:
    """Return env var value or raise ValueError if missing/empty."""
    value = env.get(key, "").strip()
    if not value:
        raise ValueError(f"{key} environment variable is required but not set")
    return value


def _env_bool(value: Optional[str], default: bool) -> bool:
    """Parse bool-like env var values. Consistent with proxy's envBool."""
    if value is None:
        return default
    v = value.strip().lower()
    if not v:
        return default
    return v in {"1", "true", "yes", "on"}


def _env_positive_int(value: Optional[str], default_str: str, upper: int) -> int:
    raw = (value or "").strip() or default_str
    try:
        n = int(raw)
    except ValueError:
        n = int(default_str)
    return max(1, min(n, upper))


def _env_positive_float(value: Optional[str], default_str: str) -> float:
    raw = (value or "").strip() or default_str
    try:
        x = float(raw)
    except ValueError:
        x = float(default_str)
    return max(0.1, x)


def _parse_database_url(url: str) -> tuple[str, int, str, str, str]:
    """Parse PostgreSQL DSN from postgresql://... URL."""
    parsed = urlparse(url)
    if parsed.scheme not in ("postgresql", "postgres"):
        raise ValueError("DATABASE_URL scheme must be postgresql:// or postgres://")
    if not parsed.hostname:
        raise ValueError("DATABASE_URL must include a host")
    user = unquote(parsed.username or "")
    password = unquote(parsed.password or "")
    host = parsed.hostname
    port = int(parsed.port or 5432)
    database = (parsed.path or "").lstrip("/").split("?")[0]
    if not database:
        raise ValueError("DATABASE_URL must include a database name in path")
    return host, port, user, password, database
