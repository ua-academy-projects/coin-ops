"""PostgreSQL connection pool and helpers."""

from __future__ import annotations

import logging
import threading
from contextlib import contextmanager
from typing import Any, Iterator, Optional

import psycopg2
from psycopg2.pool import ThreadedConnectionPool

from config import HistoryConfig

LOG = logging.getLogger("coinops.history.db")

_pg_pool_lock = threading.Lock()
_pg_pool: Optional[ThreadedConnectionPool] = None


def get_pg_pool(cfg: HistoryConfig) -> ThreadedConnectionPool:
    """Process-wide threaded pool (Flask requests + MQ consumer)."""
    global _pg_pool  # noqa: PLW0603
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
                options="-c TimeZone=UTC",
            )
        return _pg_pool


@contextmanager
def pg_conn(cfg: HistoryConfig) -> Iterator[Any]:
    """Borrow a connection from the pool; rollback on error; drop broken conns."""
    pool = get_pg_pool(cfg)
    conn = pool.getconn()
    close_conn = False
    try:
        yield conn
    except (psycopg2.OperationalError, psycopg2.InterfaceError):
        close_conn = True
        try:
            conn.rollback()
        except Exception:
            pass
        raise
    except Exception:
        try:
            conn.rollback()
        except Exception:
            close_conn = True
        raise
    finally:
        pool.putconn(conn, close=close_conn)


def verify_db_schema(cfg: HistoryConfig) -> bool:
    """
    Return True if exchange_rates is ready for the history consumer.

    Fails closed (False) if snapshot_event_id is missing.
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
