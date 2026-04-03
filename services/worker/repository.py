"""Data access layer for exchange rate history."""

from __future__ import annotations

import bisect
import logging
import uuid
from datetime import datetime, timedelta, timezone
from typing import Any, Iterable, Mapping, MutableMapping, Optional, Sequence

import psycopg2
from psycopg2.extras import execute_values

from config import HistoryConfig
from db import pg_conn

LOG = logging.getLogger("coinops.history.repo")

MAX_SERIES_POINTS = 200
SERIES_BUCKET_MINUTES = 10


# ---------------------------------------------------------------------------
# Insert
# ---------------------------------------------------------------------------


def insert_rates(
    conn: Any, rates: Iterable[Mapping[str, Any]], snapshot_event_id: str,
) -> tuple[int, int]:
    """Insert rows for one MQ event; duplicate (event, symbol, type, source) are skipped."""
    eid_str = str(uuid.UUID(snapshot_event_id))
    enriched = _enrich_crypto_uah(rates)
    rows: list[tuple[Any, ...]] = []
    for item in enriched:
        sym = str(item.get("asset_symbol", "")).strip()
        typ = str(item.get("asset_type", "")).strip()
        src = str(item.get("source", "")).strip()
        if not sym or typ not in ("fiat", "crypto") or not src:
            continue
        rows.append((sym[:16], typ[:8], item.get("price_uah"), item.get("price_usd"), src[:32], eid_str))
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


def _enrich_crypto_uah(rates: Iterable[Mapping[str, Any]]) -> list[MutableMapping[str, Any]]:
    """Set price_uah = price_usd * uah_per_usd for crypto rows missing UAH."""
    items = [dict(r) for r in rates]
    uah_per_usd: Optional[float] = None
    for it in items:
        if str(it.get("asset_type", "")).lower() != "fiat":
            continue
        if str(it.get("asset_symbol", "")).upper() != "USD":
            continue
        pu = it.get("price_uah")
        if pu is None:
            continue
        try:
            uah_per_usd = float(pu)
        except (TypeError, ValueError):
            pass
        break
    if uah_per_usd is None or uah_per_usd <= 0:
        return items
    for it in items:
        if str(it.get("asset_type", "")).lower() != "crypto":
            continue
        if it.get("price_uah") is not None:
            continue
        pusd = it.get("price_usd")
        if pusd is None:
            continue
        try:
            it["price_uah"] = round(float(pusd) * uah_per_usd, 2)
        except (TypeError, ValueError):
            pass
    return items


# ---------------------------------------------------------------------------
# History list
# ---------------------------------------------------------------------------


def fetch_history_rows(
    cfg: HistoryConfig,
    limit: int,
    asset_symbol: Optional[str],
    asset_type: Optional[str],
) -> list[dict[str, Any]]:
    """Read latest rows from DB with optional symbol/type filters."""
    clauses: list[str] = []
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
            return [
                {
                    "id": row[0],
                    "asset_symbol": row[1],
                    "asset_type": row[2],
                    "price_uah": float(row[3]) if row[3] is not None else None,
                    "price_usd": float(row[4]) if row[4] is not None else None,
                    "source": row[5],
                    "created_at": row[6].isoformat() if isinstance(row[6], datetime) else str(row[6]),
                }
                for row in cur.fetchall()
            ]


# ---------------------------------------------------------------------------
# Metrics & helpers
# ---------------------------------------------------------------------------


def metric_for_asset_type(asset_type: str) -> str:
    """Fiat: compare in UAH (official NBU-style); crypto: compare in USD."""
    return "uah" if asset_type == "fiat" else "usd"


def _value_for_metric(price_uah: Any, price_usd: Any, asset_type: str) -> Optional[float]:
    if asset_type == "fiat":
        return float(price_uah) if price_uah is not None else None
    return float(price_usd) if price_usd is not None else None


def _pct_change(old_v: Optional[float], new_v: Optional[float]) -> Optional[float]:
    if old_v is None or new_v is None or old_v == 0:
        return None
    return (new_v - old_v) / old_v * 100.0


def _fetch_single_row(
    cfg: HistoryConfig, sql: str, params: tuple[Any, ...],
) -> Optional[tuple[Any, ...]]:
    with pg_conn(cfg) as conn:
        with conn.cursor() as cur:
            cur.execute(sql, params)
            return cur.fetchone()


# ---------------------------------------------------------------------------
# Snapshots
# ---------------------------------------------------------------------------


def fetch_latest_snapshot(
    cfg: HistoryConfig, asset_symbol: str, asset_type: str,
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
    cfg: HistoryConfig, asset_symbol: str, asset_type: str, cutoff: datetime,
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


# ---------------------------------------------------------------------------
# Trends
# ---------------------------------------------------------------------------


def _compute_trend_24h_pct_conn(conn: Any, asset_symbol: str, asset_type: str) -> Optional[float]:
    """% change vs last snapshot on or before now-24h."""
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


# ---------------------------------------------------------------------------
# Sparklines
# ---------------------------------------------------------------------------


def _utc_iso_z(ts: datetime) -> str:
    """Serialize DB datetimes as UTC ISO-8601 with Z suffix."""
    ts_utc = ts.astimezone(timezone.utc) if ts.tzinfo else ts.replace(tzinfo=timezone.utc)
    ts_utc = ts_utc.replace(microsecond=0)
    s = ts_utc.isoformat()
    return s[:-6] + "Z" if s.endswith("+00:00") else s


def _rows_to_sparkline(
    rows: list[tuple[Any, ...]], asset_type: str,
) -> list[dict[str, Any]]:
    rows = list(rows)
    rows.reverse()
    out: list[dict[str, Any]] = []
    for pu, pusd, ts in rows:
        if not isinstance(ts, datetime):
            continue
        out.append(
            {
                "created_at": _utc_iso_z(ts),
                "price_uah": float(pu) if pu is not None else None,
                "price_usd": float(pusd) if pusd is not None else None,
                "series_value": _value_for_metric(pu, pusd, asset_type),
                "series_metric": metric_for_asset_type(asset_type),
            }
        )
    return out


def _fetch_sparkline_points_conn(
    conn: Any, asset_symbol: str, asset_type: str, limit: int = 24,
) -> list[dict[str, Any]]:
    """Last *limit* rows in chronological order; includes series_value for chart Y."""
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
    cfg: HistoryConfig, asset_symbol: str, asset_type: str, limit: int = 24,
) -> list[dict[str, Any]]:
    with pg_conn(cfg) as conn:
        return _fetch_sparkline_points_conn(conn, asset_symbol, asset_type, limit=limit)


# ---------------------------------------------------------------------------
# Series
# ---------------------------------------------------------------------------


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
    """Recompute pct_change_from_prev for a list of rows."""
    prev_v: Optional[float] = None
    out: list[dict[str, Any]] = []
    for row in rows:
        v = _value_for_metric(row.get("price_uah"), row.get("price_usd"), asset_type)
        pct_prev = _pct_change(prev_v, v) if prev_v is not None else None
        prev_v = v
        new_row = dict(row)
        new_row["pct_change_from_prev"] = pct_prev
        out.append(new_row)
    return out


def _bucket_series_by_minutes(
    rows: list[dict[str, Any]], asset_type: str, minutes: int,
) -> list[dict[str, Any]]:
    """At most one point per N-minute UTC window; keep the last snapshot per window."""
    if minutes <= 0 or len(rows) <= 1:
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
        buckets[int(dt.timestamp() // window_sec)] = row
    if not buckets:
        return _recompute_pct_series(rows, asset_type)
    ordered = [buckets[k] for k in sorted(buckets.keys())]
    return _recompute_pct_series(ordered, asset_type)


def _thin_series_to_max_points(
    rows: list[dict[str, Any]], asset_type: str, max_points: int,
) -> list[dict[str, Any]]:
    if len(rows) <= max_points:
        return rows
    idxs = _uniform_sample_row_indices(len(rows), max_points)
    picked = [rows[i] for i in idxs]
    return _recompute_pct_series(picked, asset_type)


def _backfill_crypto_uah_series(conn: Any, rows: list[dict[str, Any]]) -> None:
    """Fill missing price_uah for crypto series using closest USD/UAH rate."""
    need = [r for r in rows if r.get("price_uah") is None and r.get("price_usd") is not None]
    if not need:
        return
    ts_min = min((r["created_at"] for r in need), default=None)
    ts_max = max((r["created_at"] for r in need), default=None)
    if ts_min is None:
        return
    usd_sql = """
        SELECT price_uah, created_at
        FROM exchange_rates
        WHERE asset_symbol = 'USD' AND asset_type = 'fiat'
          AND created_at >= (%s::timestamptz - interval '1 day')
          AND created_at <= (%s::timestamptz + interval '1 day')
        ORDER BY created_at ASC
    """
    with conn.cursor() as cur:
        cur.execute(usd_sql, (ts_min, ts_max))
        usd_rows = cur.fetchall()
    if not usd_rows:
        return
    usd_ts: list[float] = []
    usd_vals: list[float] = []
    for pu, ts in usd_rows:
        if pu is None or not isinstance(ts, datetime):
            continue
        if ts.tzinfo is None:
            ts = ts.replace(tzinfo=timezone.utc)
        usd_ts.append(ts.timestamp())
        usd_vals.append(float(pu))
    if not usd_ts:
        return
    for r in need:
        try:
            dt = datetime.fromisoformat(r["created_at"].replace("Z", "+00:00"))
        except (ValueError, AttributeError):
            continue
        t = dt.timestamp()
        idx = bisect.bisect_left(usd_ts, t)
        best = None
        for ci in (idx - 1, idx):
            if 0 <= ci < len(usd_ts):
                if best is None or abs(usd_ts[ci] - t) < abs(usd_ts[best] - t):
                    best = ci
        if best is not None:
            r["price_uah"] = round(float(r["price_usd"]) * usd_vals[best], 2)


def fetch_series_for_range(
    cfg: HistoryConfig,
    asset_symbol: str,
    asset_type: str,
    range_key: str,
    date_from: str | None = None,
    date_to: str | None = None,
) -> list[dict[str, Any]]:
    """Chronological snapshots with pct_change_from_prev on one metric (UAH or USD)."""
    rk = (range_key or "7d").lower().strip()
    if rk not in {"7d", "30d", "all", "24h", "custom"}:
        rk = "7d"
    clauses = ["asset_symbol = %s", "asset_type = %s"]
    params: list[Any] = [asset_symbol.upper(), asset_type]
    if rk == "custom":
        if date_from:
            clauses.append("created_at >= %s")
            params.append(date_from + " 00:00:00+00")
        if date_to:
            clauses.append("created_at <= %s")
            params.append(date_to + " 23:59:59+00")
    elif rk == "7d":
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

        metric = metric_for_asset_type(asset_type)
        out: list[dict[str, Any]] = []
        for pu, pusd, ts in raw_rows:
            if not isinstance(ts, datetime):
                continue
            out.append(
                {
                    "created_at": _utc_iso_z(ts),
                    "price_uah": float(pu) if pu is not None else None,
                    "price_usd": float(pusd) if pusd is not None else None,
                    "series_metric": metric,
                }
            )

        if asset_type == "crypto":
            _backfill_crypto_uah_series(conn, out)

    bucketed = _bucket_series_by_minutes(out, asset_type, SERIES_BUCKET_MINUTES)
    return _thin_series_to_max_points(bucketed, asset_type, MAX_SERIES_POINTS)


# ---------------------------------------------------------------------------
# Dashboard
# ---------------------------------------------------------------------------


def parse_asset_pairs(pairs_param: str) -> list[tuple[str, str]]:
    """Parse ``USD:fiat,EUR:fiat`` into [(USD, fiat), ...]."""
    out: list[tuple[str, str]] = []
    for part in pairs_param.split(","):
        part = part.strip()
        if not part or ":" not in part:
            continue
        sym, typ = part.split(":", 1)
        sym = sym.strip().upper()
        typ = typ.strip().lower()
        if typ not in ("fiat", "crypto") or not sym:
            continue
        out.append((sym, typ))
    return out


def build_dashboard_items(
    cfg: HistoryConfig, pairs: Sequence[tuple[str, str]],
) -> list[dict[str, Any]]:
    """One DB connection for all pairs to reduce pool churn under dashboard load."""
    items: list[dict[str, Any]] = []
    with pg_conn(cfg) as conn:
        for sym, typ in pairs:
            trend = _compute_trend_24h_pct_conn(conn, sym, typ)
            spark = _fetch_sparkline_points_conn(conn, sym, typ, limit=24)
            items.append(
                {
                    "asset_symbol": sym,
                    "asset_type": typ,
                    "series_metric": metric_for_asset_type(typ),
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
