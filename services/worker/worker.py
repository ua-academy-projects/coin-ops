#!/usr/bin/python3

"""
CoinOps history service (VM3).

Responsibilities in Phase A:
1) Consume normalized snapshot events from RabbitMQ and persist rates to PostgreSQL.
2) Expose historical records over HTTP: ``GET /api/v1/history``, ``GET /api/v1/history/series``,
   ``GET /api/v1/history/dashboard`` (тренди та спарклайни; % для фіату в UAH, для крипти в USD).
"""

from __future__ import annotations

import json
import logging
import os
import random
import sys
import threading
import time
import uuid
from contextlib import contextmanager
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Any, Iterable, Iterator, Mapping, MutableMapping, Optional, Sequence, Tuple
from urllib.parse import unquote, urlparse

import pika
import psycopg2
from flask import Flask, Response, jsonify, request
from psycopg2.extras import execute_values
from psycopg2.pool import ThreadedConnectionPool

LOG = logging.getLogger("coinops.history")

# Max points returned for history series (chart + table); larger series are uniformly sampled.
MAX_SERIES_POINTS = 200
# Згортання «напливу» знімків: не більше однієї точки на інтервал (узгоджено з типовим кроком ~10 хв).
SERIES_BUCKET_MINUTES = 10

_pg_pool_lock = threading.Lock()
_pg_pool: Optional[ThreadedConnectionPool] = None

_DEFAULT_PG_HOST = "10.10.1.6"
_DEFAULT_PG_PORT = "5432"
_DEFAULT_PG_USER = "coinops"
_DEFAULT_PG_DB = "coinops_db"
_DEFAULT_MQ_URL = "amqp://coinops:coinops@10.10.1.5:5672/"
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
    def from_environ(cls, environ: Optional[MutableMapping[str, str]] = None) -> "HistoryConfig":
        """Load config from env vars; DATABASE_URL overrides PG* variables."""
        env = environ if environ is not None else os.environ
        db_url = env.get("DATABASE_URL", "").strip()
        if db_url:
            host, port, user, password, database = _parse_database_url(db_url)
        else:
            host = env.get("PGHOST", _DEFAULT_PG_HOST)
            port = int(env.get("PGPORT", _DEFAULT_PG_PORT))
            user = env.get("PGUSER", _DEFAULT_PG_USER)
            password = env.get("PGPASSWORD", "")
            database = env.get("PGDATABASE", _DEFAULT_PG_DB)
        if not password:
            raise ValueError("PGPASSWORD or DATABASE_URL with password is required")
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
            rabbitmq_url=env.get("RABBITMQ_URL", _DEFAULT_MQ_URL),
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


def _env_bool(value: Optional[str], default: bool) -> bool:
    """Parse bool-like env var values."""
    if value is None:
        return default
    return value.lower() in {"1", "true", "yes", "on"}


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


def verify_db_schema(cfg: HistoryConfig) -> bool:
    """
    Return True if exchange_rates is ready for the history consumer.

    Fails closed (False) if snapshot_event_id is missing — inserts will error until DB matches init.sql.
    """
    try:
        with pg_conn(cfg) as conn:
            with conn.cursor() as cur:
                cur.execute(
                    """
                    SELECT 1
                    FROM information_schema.columns
                    WHERE table_schema = 'public'
                      AND table_name = 'exchange_rates'
                      AND column_name = 'snapshot_event_id'
                    LIMIT 1
                    """
                )
                ok = cur.fetchone() is not None
        if not ok:
            LOG.critical(
                "PostgreSQL: column public.exchange_rates.snapshot_event_id is missing. "
                "Apply services/database/init.sql on a fresh VM or ALTER the table; "
                "otherwise the MQ consumer cannot persist rows."
            )
        return ok
    except psycopg2.Error as exc:
        LOG.critical("PostgreSQL schema check failed: %s", exc)
        return False


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


def get_pg_pool(cfg: HistoryConfig) -> ThreadedConnectionPool:
    """Process-wide threaded pool (Flask requests + MQ consumer)."""
    global _pg_pool  # pylint: disable=global-statement
    with _pg_pool_lock:
        if _pg_pool is None:
            _pg_pool = ThreadedConnectionPool(
                minconn=1,
                maxconn=32,
                host=cfg.pg_host,
                port=cfg.pg_port,
                user=cfg.pg_user,
                password=cfg.pg_password,
                dbname=cfg.pg_database,
                # Ensure TIMESTAMPTZ is fetched as an unambiguous instant.
                # psycopg2 may return naive datetimes depending on session settings;
                # keeping the DB session timezone UTC prevents +3h shifts on serialization.
                options="-c TimeZone=UTC",
            )
        return _pg_pool


@contextmanager
def pg_conn(cfg: HistoryConfig) -> Iterator[Any]:
    """Borrow a connection from the pool; rollback on error; drop broken conns from the pool."""
    pool = get_pg_pool(cfg)
    conn = pool.getconn()
    close_conn = False
    try:
        yield conn
    except (psycopg2.OperationalError, psycopg2.InterfaceError):
        close_conn = True
        try:
            conn.rollback()
        except Exception:  # pylint: disable=broad-except
            pass
        raise
    except Exception:
        try:
            conn.rollback()
        except Exception:  # pylint: disable=broad-except
            close_conn = True
        raise
    finally:
        pool.putconn(conn, close=close_conn)


def _stable_event_id(body: bytes, payload: Mapping[str, Any]) -> str:
    """Prefer proxy event_id; otherwise derive a stable UUID from raw bytes (redelivery-safe)."""
    raw = payload.get("event_id")
    if isinstance(raw, str) and raw.strip():
        try:
            return str(uuid.UUID(raw.strip()))
        except ValueError:
            pass
    return str(uuid.uuid5(uuid.NAMESPACE_OID, body))


def insert_rates(conn: Any, rates: Iterable[Mapping[str, Any]], snapshot_event_id: str) -> tuple[int, int]:
    """Insert rows for one MQ event; duplicate (event, symbol, type, source) are skipped (idempotent)."""
    # Use str, not uuid.UUID: psycopg2's execute_values does not adapt UUID by default on all builds.
    eid_str = str(uuid.UUID(snapshot_event_id))
    rows: list[tuple[Any, ...]] = []
    for item in rates:
        sym = str(item.get("asset_symbol", "")).strip()
        typ = str(item.get("asset_type", "")).strip()
        src = str(item.get("source", "")).strip()
        if not sym or typ not in ("fiat", "crypto") or not src:
            continue
        rows.append(
            (
                sym[:16],
                typ[:8],
                item.get("price_uah"),
                item.get("price_usd"),
                src[:32],
                eid_str,
            )
        )
    if not rows:
        return 0, 0
    sql = """
        INSERT INTO exchange_rates (asset_symbol, asset_type, price_uah, price_usd, source, snapshot_event_id)
        VALUES %s
        ON CONFLICT ON CONSTRAINT uq_exchange_rates_snapshot_line DO NOTHING
    """
    try:
        with conn.cursor() as cur:
            execute_values(cur, sql, rows, page_size=500)
            raw_rc = cur.rowcount
    except psycopg2.Error:
        LOG.exception("insert_rates failed (snapshot_event_id=%s)", snapshot_event_id)
        raise
    inserted = raw_rc if isinstance(raw_rc, int) and raw_rc >= 0 else 0
    return inserted, len(rows)


def _mq_body_to_bytes(body: Any) -> bytes:
    """pika may deliver ``bytes``, ``bytearray``, or ``memoryview``."""
    if isinstance(body, memoryview):
        return body.tobytes()
    if isinstance(body, bytearray):
        return bytes(body)
    if isinstance(body, bytes):
        return body
    return bytes(body)


def _decode_event(body: Any) -> tuple[str, list[dict[str, Any]], bool]:
    """
    Return (snapshot_event_id, rates, malformed).

    If malformed is True (invalid UTF-8/JSON or non-object root), the consumer should ACK
    without requeue to avoid a poison-message loop (no DLX assumed).
    """
    body = _mq_body_to_bytes(body)
    try:
        text = body.decode("utf-8")
    except UnicodeDecodeError:
        LOG.warning("mq payload: invalid utf-8 (%d bytes)", len(body))
        return str(uuid.uuid5(uuid.NAMESPACE_OID, body)), [], True
    try:
        parsed: Any = json.loads(text)
    except json.JSONDecodeError as exc:
        LOG.warning("mq payload: invalid json: %s", exc)
        return str(uuid.uuid5(uuid.NAMESPACE_OID, body)), [], True
    if not isinstance(parsed, dict):
        LOG.warning("mq payload: root is not an object")
        return str(uuid.uuid5(uuid.NAMESPACE_OID, body)), [], True
    payload: Mapping[str, Any] = parsed
    event_id = _stable_event_id(body, payload)
    data = payload.get("data")
    if not isinstance(data, dict):
        return event_id, [], False
    rates_raw = data.get("rates")
    # Go encodes a nil slice as JSON null; treat like [] so we do not skip valid envelopes.
    if rates_raw is None:
        rates_list: list[dict[str, Any]] = []
    elif isinstance(rates_raw, list):
        rates_list = [r for r in rates_raw if isinstance(r, dict)]
    else:
        LOG.warning("mq payload: data.rates has unexpected type %s", type(rates_raw).__name__)
        return event_id, [], False
    return event_id, rates_list, False


def _sleep_interruptible(stop_event: threading.Event, seconds: float) -> None:
    """Sleep up to ``seconds`` but return early if ``stop_event`` is set."""
    if seconds <= 0:
        return
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        if stop_event.wait(0.2):
            return


def run_consumer_forever(cfg: HistoryConfig, stop_event: threading.Event) -> None:
    """
    Run RabbitMQ consumer loop with reconnects.

    Messages are ACKed only after successful DB commit.
    """
    reconnect_attempt = 0
    while not stop_event.is_set():
        connection = None
        channel = None
        try:
            params = pika.URLParameters(cfg.rabbitmq_url)
            connection = pika.BlockingConnection(params)
            channel = connection.channel()
            channel.exchange_declare(exchange=cfg.rabbitmq_exchange, exchange_type="direct", durable=True)
            channel.queue_declare(queue=cfg.rabbitmq_queue, durable=True)
            channel.queue_bind(
                queue=cfg.rabbitmq_queue,
                exchange=cfg.rabbitmq_exchange,
                routing_key=cfg.rabbitmq_routing_key,
            )
            channel.basic_qos(prefetch_count=cfg.mq_prefetch_count)
            reconnect_attempt = 0
            LOG.info(
                "history consumer connected exchange=%s queue=%s key=%s prefetch=%d",
                cfg.rabbitmq_exchange,
                cfg.rabbitmq_queue,
                cfg.rabbitmq_routing_key,
                cfg.mq_prefetch_count,
            )
            while not stop_event.is_set():
                method, properties, body = channel.basic_get(queue=cfg.rabbitmq_queue, auto_ack=False)
                if method is None:
                    time.sleep(0.2)
                    continue
                try:
                    event_id, rates, malformed = _decode_event(body)
                    if malformed or not rates:
                        if malformed:
                            LOG.warning("ack malformed mq message, delivery_tag=%s", method.delivery_tag)
                        elif not rates:
                            LOG.debug(
                                "ack mq message with no rate rows (event_id=%s), delivery_tag=%s",
                                event_id,
                                method.delivery_tag,
                            )
                        channel.basic_ack(method.delivery_tag)
                        continue
                    with pg_conn(cfg) as conn:
                        inserted, attempted = insert_rates(conn, rates, event_id)
                        conn.commit()
                        LOG.info(
                            "history consumer persisted %d/%d rows (snapshot_event_id=%s)",
                            inserted,
                            attempted,
                            event_id,
                        )
                    channel.basic_ack(method.delivery_tag)
                except Exception as exc:  # pylint: disable=broad-except
                    LOG.exception("consume/insert failed: %s", exc)
                    # Requeue to avoid data loss; in real setup add DLQ and retry limits.
                    channel.basic_nack(method.delivery_tag, requeue=True)
                _ = properties
        except Exception as exc:  # pylint: disable=broad-except
            reconnect_attempt += 1
            exp = min(10, max(0, reconnect_attempt - 1))
            delay = min(cfg.mq_backoff_max, cfg.mq_backoff_initial * (2**exp))
            delay *= 0.5 + random.random()
            LOG.warning(
                "consumer reconnect after error (attempt %d, sleep %.1fs): %s",
                reconnect_attempt,
                delay,
                exc,
            )
            _sleep_interruptible(stop_event, delay)
        finally:
            try:
                if channel and channel.is_open:
                    channel.close()
            except Exception:  # pylint: disable=broad-except
                pass
            try:
                if connection and connection.is_open:
                    connection.close()
            except Exception:  # pylint: disable=broad-except
                pass


def fetch_history_rows(
    cfg: HistoryConfig,
    limit: int,
    asset_symbol: Optional[str],
    asset_type: Optional[str],
) -> list[dict[str, Any]]:
    """Read latest rows from DB with optional symbol/type filters."""
    clauses = []
    params: list[Any] = []
    if asset_symbol:
        clauses.append("asset_symbol = %s")
        params.append(asset_symbol.upper())
    if asset_type in {"fiat", "crypto"}:
        clauses.append("asset_type = %s")
        params.append(asset_type)

    where = ("WHERE " + " AND ".join(clauses)) if clauses else ""
    sql = f"""
        SELECT id, asset_symbol, asset_type, price_uah, price_usd, source, created_at
        FROM exchange_rates
        {where}
        ORDER BY created_at DESC
        LIMIT %s
    """
    params.append(limit)

    with pg_conn(cfg) as conn:
        with conn.cursor() as cur:
            cur.execute(sql, tuple(params))
            out = []
            for row in cur.fetchall():
                out.append(
                    {
                        "id": row[0],
                        "asset_symbol": row[1],
                        "asset_type": row[2],
                        "price_uah": float(row[3]) if row[3] is not None else None,
                        "price_usd": float(row[4]) if row[4] is not None else None,
                        "source": row[5],
                        "created_at": row[6].isoformat() if isinstance(row[6], datetime) else str(row[6]),
                    }
                )
            return out


def _metric_for_asset_type(asset_type: str) -> str:
    """Fiat: compare in UAH (official NBU-style); crypto: compare in USD."""
    return "uah" if asset_type == "fiat" else "usd"


def _value_for_metric(price_uah: Any, price_usd: Any, asset_type: str) -> Optional[float]:
    if asset_type == "fiat":
        if price_uah is None:
            return None
        return float(price_uah)
    if price_usd is None:
        return None
    return float(price_usd)


def _pct_change(old_v: Optional[float], new_v: Optional[float]) -> Optional[float]:
    if old_v is None or new_v is None or old_v == 0:
        return None
    return (new_v - old_v) / old_v * 100.0


def _fetch_single_row(
    cfg: HistoryConfig,
    sql: str,
    params: tuple[Any, ...],
) -> Optional[tuple[Any, ...]]:
    with pg_conn(cfg) as conn:
        with conn.cursor() as cur:
            cur.execute(sql, params)
            return cur.fetchone()


def fetch_latest_snapshot(
    cfg: HistoryConfig,
    asset_symbol: str,
    asset_type: str,
) -> Optional[tuple[Optional[float], Optional[float], datetime]]:
    """Return (price_uah, price_usd, created_at) for latest row or None."""
    row = _fetch_single_row(
        cfg,
        """
        SELECT price_uah, price_usd, created_at
        FROM exchange_rates
        WHERE asset_symbol = %s AND asset_type = %s
        ORDER BY created_at DESC
        LIMIT 1
        """,
        (asset_symbol.upper(), asset_type),
    )
    if not row:
        return None
    pu, pusd, ts = row[0], row[1], row[2]
    if not isinstance(ts, datetime):
        return None
    return (
        float(pu) if pu is not None else None,
        float(pusd) if pusd is not None else None,
        ts if ts.tzinfo else ts.replace(tzinfo=timezone.utc),
    )


def fetch_snapshot_on_or_before(
    cfg: HistoryConfig,
    asset_symbol: str,
    asset_type: str,
    cutoff: datetime,
) -> Optional[tuple[Optional[float], Optional[float], datetime]]:
    row = _fetch_single_row(
        cfg,
        """
        SELECT price_uah, price_usd, created_at
        FROM exchange_rates
        WHERE asset_symbol = %s AND asset_type = %s AND created_at <= %s
        ORDER BY created_at DESC
        LIMIT 1
        """,
        (asset_symbol.upper(), asset_type, cutoff),
    )
    if not row:
        return None
    pu, pusd, ts = row[0], row[1], row[2]
    if not isinstance(ts, datetime):
        return None
    return (
        float(pu) if pu is not None else None,
        float(pusd) if pusd is not None else None,
        ts if ts.tzinfo else ts.replace(tzinfo=timezone.utc),
    )


def _compute_trend_24h_pct_conn(conn: Any, asset_symbol: str, asset_type: str) -> Optional[float]:
    """% change vs last snapshot on or before now-24h; same metric as series (UAH fiat, USD crypto)."""
    now = datetime.now(timezone.utc)
    cutoff = now - timedelta(hours=24)
    sym = asset_symbol.upper()
    with conn.cursor() as cur:
        cur.execute(
            """
            SELECT
              l.price_uah, l.price_usd, l.created_at,
              o.price_uah, o.price_usd, o.created_at
            FROM (
              SELECT price_uah, price_usd, created_at
              FROM exchange_rates
              WHERE asset_symbol = %s AND asset_type = %s
              ORDER BY created_at DESC
              LIMIT 1
            ) l
            CROSS JOIN (
              SELECT price_uah, price_usd, created_at
              FROM exchange_rates
              WHERE asset_symbol = %s AND asset_type = %s AND created_at <= %s
              ORDER BY created_at DESC
              LIMIT 1
            ) o
            """,
            (sym, asset_type, sym, asset_type, cutoff),
        )
        row = cur.fetchone()
    if not row:
        return None
    lu, lusd, lts, ou, ousd, ots = row[0], row[1], row[2], row[3], row[4], row[5]
    if not isinstance(lts, datetime) or not isinstance(ots, datetime):
        return None
    new_v = _value_for_metric(lu, lusd, asset_type)
    old_v = _value_for_metric(ou, ousd, asset_type)
    return _pct_change(old_v, new_v)


def compute_trend_24h_pct(cfg: HistoryConfig, asset_symbol: str, asset_type: str) -> Optional[float]:
    with pg_conn(cfg) as conn:
        return _compute_trend_24h_pct_conn(conn, asset_symbol, asset_type)


def _rows_to_sparkline(
    rows: list[tuple[Any, ...]],
    asset_type: str,
) -> list[dict[str, Any]]:
    rows = list(rows)
    rows.reverse()
    out: list[dict[str, Any]] = []
    for pu, pusd, ts in rows:
        if not isinstance(ts, datetime):
            continue
        ts_iso = _utc_iso_z(ts)
        sv = _value_for_metric(pu, pusd, asset_type)
        out.append(
            {
                "created_at": ts_iso,
                "price_uah": float(pu) if pu is not None else None,
                "price_usd": float(pusd) if pusd is not None else None,
                "series_value": sv,
                "series_metric": _metric_for_asset_type(asset_type),
            }
        )
    return out


def _utc_iso_z(ts: datetime) -> str:
    """Serialize DB datetimes as UTC ISO-8601 with `Z` suffix.

    Important: avoid "naive datetime treated as UTC" ambiguity when psycopg2 returns
    timezone-less datetimes based on the DB session settings.
    """
    # With `SET TimeZone=UTC` above, naive datetimes are in UTC already.
    ts_utc = ts.astimezone(timezone.utc) if ts.tzinfo else ts.replace(tzinfo=timezone.utc)
    ts_utc = ts_utc.replace(microsecond=0)
    s = ts_utc.isoformat()
    return s[:-6] + "Z" if s.endswith("+00:00") else s


def _fetch_sparkline_points_conn(
    conn: Any,
    asset_symbol: str,
    asset_type: str,
    limit: int = 24,
) -> list[dict[str, Any]]:
    """Last ``limit`` rows, chronological order; includes series_value for chart Y."""
    with conn.cursor() as cur:
        cur.execute(
            """
            SELECT price_uah, price_usd, created_at
            FROM exchange_rates
            WHERE asset_symbol = %s AND asset_type = %s
            ORDER BY created_at DESC
            LIMIT %s
            """,
            (asset_symbol.upper(), asset_type, limit),
        )
        raw = cur.fetchall()
    return _rows_to_sparkline(list(raw), asset_type)


def fetch_sparkline_points(
    cfg: HistoryConfig,
    asset_symbol: str,
    asset_type: str,
    limit: int = 24,
) -> list[dict[str, Any]]:
    with pg_conn(cfg) as conn:
        return _fetch_sparkline_points_conn(conn, asset_symbol, asset_type, limit=limit)


def _uniform_sample_row_indices(n: int, k: int) -> list[int]:
    """Return sorted unique indices in [0, n-1], up to k points spread across the range."""
    if n <= 0 or k <= 0:
        return []
    if k >= n:
        return list(range(n))
    if k == 1:
        return [0]
    raw = [int(round(i * (n - 1) / (k - 1))) for i in range(k)]
    out: list[int] = []
    seen: set[int] = set()
    for idx in raw:
        idx = max(0, min(n - 1, idx))
        if idx not in seen:
            seen.add(idx)
            out.append(idx)
    return sorted(out)


def _recompute_pct_series(rows: list[dict[str, Any]], asset_type: str) -> list[dict[str, Any]]:
    """Recompute pct_change_from_prev for a list of rows (same metric as series)."""
    prev_v: Optional[float] = None
    out: list[dict[str, Any]] = []
    for row in rows:
        pu = row.get("price_uah")
        pusd = row.get("price_usd")
        v = _value_for_metric(pu, pusd, asset_type)
        pct_prev = _pct_change(prev_v, v) if prev_v is not None else None
        prev_v = v
        new_row = dict(row)
        new_row["pct_change_from_prev"] = pct_prev
        out.append(new_row)
    return out


def _bucket_series_by_minutes(
    rows: list[dict[str, Any]], asset_type: str, minutes: int
) -> list[dict[str, Any]]:
    """Щонайбільше одна точка на ``minutes``-хвилинне UTC-вікно; лишається останній знімок у вікні."""
    if minutes <= 0:
        return _recompute_pct_series(rows, asset_type)
    if len(rows) <= 1:
        return _recompute_pct_series(rows, asset_type)
    window_sec = float(minutes * 60)
    buckets: dict[int, dict[str, Any]] = {}
    for row in rows:
        ts = row.get("created_at")
        if not ts or not isinstance(ts, str):
            continue
        try:
            dt = datetime.fromisoformat(ts.replace("Z", "+00:00"))
        except ValueError:
            continue
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        key = int(dt.timestamp() // window_sec)
        buckets[key] = row
    if not buckets:
        return _recompute_pct_series(rows, asset_type)
    ordered = [buckets[k] for k in sorted(buckets.keys())]
    return _recompute_pct_series(ordered, asset_type)


def _thin_series_to_max_points(
    rows: list[dict[str, Any]], asset_type: str, max_points: int
) -> list[dict[str, Any]]:
    if len(rows) <= max_points:
        return rows
    idxs = _uniform_sample_row_indices(len(rows), max_points)
    picked = [rows[i] for i in idxs]
    return _recompute_pct_series(picked, asset_type)


def fetch_series_for_range(
    cfg: HistoryConfig,
    asset_symbol: str,
    asset_type: str,
    range_key: str,
) -> list[dict[str, Any]]:
    """Chronological snapshots with pct_change_from_prev on one metric (UAH or USD)."""
    rk = (range_key or "7d").lower().strip()
    if rk not in {"7d", "30d", "all", "24h"}:
        rk = "7d"
    clauses = ["asset_symbol = %s", "asset_type = %s"]
    params: list[Any] = [asset_symbol.upper(), asset_type]
    if rk == "7d":
        clauses.append("created_at >= %s")
        params.append(datetime.now(timezone.utc) - timedelta(days=7))
    elif rk == "30d":
        clauses.append("created_at >= %s")
        params.append(datetime.now(timezone.utc) - timedelta(days=30))
    elif rk == "24h":
        clauses.append("created_at >= %s")
        params.append(datetime.now(timezone.utc) - timedelta(hours=24))
    where_sql = " AND ".join(clauses)
    sql = f"""
        SELECT price_uah, price_usd, created_at
        FROM exchange_rates
        WHERE {where_sql}
        ORDER BY created_at ASC
        LIMIT 10000
    """
    with pg_conn(cfg) as conn:
        with conn.cursor() as cur:
            cur.execute(sql, tuple(params))
            raw_rows = cur.fetchall()

    metric = _metric_for_asset_type(asset_type)
    out: list[dict[str, Any]] = []
    for pu, pusd, ts in raw_rows:
        if not isinstance(ts, datetime):
            continue
        ts_iso = _utc_iso_z(ts)
        out.append(
            {
                "created_at": ts_iso,
                "price_uah": float(pu) if pu is not None else None,
                "price_usd": float(pusd) if pusd is not None else None,
                "series_metric": metric,
            }
        )
    bucketed = _bucket_series_by_minutes(out, asset_type, SERIES_BUCKET_MINUTES)
    return _thin_series_to_max_points(bucketed, asset_type, MAX_SERIES_POINTS)


def parse_asset_pairs(pairs_param: str) -> list[Tuple[str, str]]:
    """Parse ``USD:fiat,EUR:fiat`` into [(USD, fiat), ...]."""
    out: list[Tuple[str, str]] = []
    for part in pairs_param.split(","):
        part = part.strip()
        if not part:
            continue
        if ":" not in part:
            continue
        sym, typ = part.split(":", 1)
        sym = sym.strip().upper()
        typ = typ.strip().lower()
        if typ not in ("fiat", "crypto") or not sym:
            continue
        out.append((sym, typ))
    return out


def build_dashboard_items(
    cfg: HistoryConfig,
    pairs: Sequence[Tuple[str, str]],
) -> list[dict[str, Any]]:
    """One DB connection for all pairs to reduce pool churn under dashboard load."""
    items: list[dict[str, Any]] = []
    with pg_conn(cfg) as conn:
        for sym, typ in pairs:
            trend = _compute_trend_24h_pct_conn(conn, sym, typ)
            spark = _fetch_sparkline_points_conn(conn, sym, typ, limit=24)
            metric = _metric_for_asset_type(typ)
            items.append(
                {
                    "asset_symbol": sym,
                    "asset_type": typ,
                    "series_metric": metric,
                    "trend_24h_pct": trend,
                    "trend_24h_note": (
                        "Порівняння з останнім знімком у БД на момент або до «зараз мінус 24 год»; "
                        "якщо знімків не було — значення недоступне."
                    ),
                    "sparkline_points": spark,
                    "sparkline_note": (
                        "Останні 24 записи в історії (не обовʼязково рівно 24 години реального часу)."
                    ),
                }
            )
    return items


def _install_api_hardening(app: Flask, cors_allow_origin: str) -> None:
    """Security headers; optional CORS when HISTORY_CORS_ALLOW_ORIGIN is set."""

    @app.after_request
    def _security_headers(response: Response) -> Response:
        response.headers.setdefault("X-Content-Type-Options", "nosniff")
        response.headers.setdefault("X-Frame-Options", "DENY")
        response.headers.setdefault("Referrer-Policy", "no-referrer")
        if cors_allow_origin:
            response.headers["Access-Control-Allow-Origin"] = cors_allow_origin
        return response

    if not cors_allow_origin:
        return

    @app.before_request
    def _cors_preflight() -> Optional[Response]:
        if request.method != "OPTIONS":
            return None
        resp = Response(status=204)
        resp.headers["Access-Control-Allow-Origin"] = cors_allow_origin
        resp.headers["Access-Control-Allow-Methods"] = "GET, OPTIONS"
        resp.headers["Access-Control-Allow-Headers"] = "Content-Type, Accept"
        return resp


def create_app(cfg: HistoryConfig) -> Flask:
    """Create HTTP API for historical data."""
    app = Flask(__name__)
    _install_api_hardening(app, cfg.history_cors_allow_origin)

    @app.get("/healthz")
    def healthz() -> Any:
        return {"status": "ok", "service": "history"}

    @app.get("/api/v1/history")
    def history() -> Any:
        try:
            limit = int(request.args.get("limit", "50"))
        except ValueError:
            limit = 50
        limit = max(1, min(limit, 500))
        symbol = request.args.get("asset_symbol")
        asset_type = request.args.get("asset_type")
        try:
            rows = fetch_history_rows(cfg, limit=limit, asset_symbol=symbol, asset_type=asset_type)
            return jsonify({"items": rows, "count": len(rows), "generated_at": datetime.now(timezone.utc).isoformat()})
        except Exception as exc:  # pylint: disable=broad-except
            LOG.exception("history query failed: %s", exc)
            return jsonify({"error": "history_query_failed", "detail": str(exc)}), 500

    @app.get("/api/v1/history/series")
    def history_series() -> Any:
        symbol = (request.args.get("asset_symbol") or "").strip().upper()
        asset_type = (request.args.get("asset_type") or "").strip().lower()
        range_key = (request.args.get("range") or "7d").strip()
        if not symbol or asset_type not in ("fiat", "crypto"):
            return jsonify({"error": "invalid_params", "detail": "asset_symbol and asset_type (fiat|crypto) required"}), 400
        try:
            rows = fetch_series_for_range(cfg, symbol, asset_type, range_key)
            return jsonify(
                {
                    "asset_symbol": symbol,
                    "asset_type": asset_type,
                    "range": range_key,
                    "series_metric": _metric_for_asset_type(asset_type),
                    "items": rows,
                    "count": len(rows),
                    "generated_at": datetime.now(timezone.utc).isoformat(),
                }
            )
        except Exception as exc:  # pylint: disable=broad-except
            LOG.exception("history series failed: %s", exc)
            return jsonify({"error": "history_series_failed", "detail": str(exc)}), 500

    @app.get("/api/v1/history/dashboard")
    def history_dashboard() -> Any:
        pairs_raw = request.args.get("pairs") or ""
        pairs = parse_asset_pairs(pairs_raw)
        if not pairs:
            return jsonify({"error": "invalid_params", "detail": "pairs=USD:fiat,EUR:fiat,... required"}), 400
        if len(pairs) > 80:
            return jsonify({"error": "invalid_params", "detail": "too many pairs (max 80)"}), 400
        try:
            items = build_dashboard_items(cfg, pairs)
            return jsonify(
                {
                    "items": items,
                    "count": len(items),
                    "generated_at": datetime.now(timezone.utc).isoformat(),
                }
            )
        except Exception as exc:  # pylint: disable=broad-except
            LOG.exception("history dashboard failed: %s", exc)
            return jsonify({"error": "history_dashboard_failed", "detail": str(exc)}), 500

    return app


def main() -> None:
    """Boot consumer thread and/or HTTP API according to env flags."""
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s %(message)s",
        stream=sys.stdout,
    )
    try:
        cfg = HistoryConfig.from_environ()
    except ValueError as exc:
        LOG.error("configuration error: %s", exc)
        sys.exit(1)

    get_pg_pool(cfg)
    if cfg.mq_consumer_enabled:
        verify_db_schema(cfg)

    LOG.info(
        "history service db=%s@%s:%s/%s mq=%s http=%s:%s consumer=%s api=%s",
        cfg.pg_user,
        cfg.pg_host,
        cfg.pg_port,
        cfg.pg_database,
        cfg.rabbitmq_url,
        cfg.history_listen,
        cfg.history_port,
        cfg.mq_consumer_enabled,
        cfg.http_api_enabled,
    )

    stop_event = threading.Event()
    if cfg.mq_consumer_enabled:
        thread = threading.Thread(target=run_consumer_forever, args=(cfg, stop_event), daemon=True)
        thread.start()

    if cfg.http_api_enabled:
        app = create_app(cfg)
        app.run(host=cfg.history_listen, port=cfg.history_port)
        return

    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        stop_event.set()


if __name__ == "__main__":
    main()
