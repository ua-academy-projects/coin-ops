"""
Domain helpers for the CoinOps Flask frontend.

Pure functions that transform proxy / API payloads —
no Flask or HTTP dependencies.
"""

from __future__ import annotations

import logging
from datetime import datetime, timezone
from typing import Any, Optional, Tuple

import requests

LOG = logging.getLogger("coinops.frontend")


# ---------------------------------------------------------------------------
# Rate enrichment
# ---------------------------------------------------------------------------

def enrich_rates_with_crypto_uah(rates: list) -> None:
    """
    For crypto rows, set ``price_uah`` = ``price_usd * uah_per_usd`` where
    ``uah_per_usd`` is the official UAH price of USD (NBU) from the USD fiat row.

    Mutates rate dicts in place. Round to 2 decimals.
    """
    uah_per_usd: Optional[float] = None
    for item in rates:
        if not isinstance(item, dict):
            continue
        if str(item.get("asset_type", "")).lower() != "fiat":
            continue
        if str(item.get("asset_symbol", "")).upper() != "USD":
            continue
        pu = item.get("price_uah")
        if pu is None:
            continue
        try:
            uah_per_usd = float(pu)
        except (TypeError, ValueError):
            pass
        break

    if uah_per_usd is None or uah_per_usd <= 0:
        return

    for item in rates:
        if not isinstance(item, dict):
            continue
        if str(item.get("asset_type", "")).lower() != "crypto":
            continue
        pusd = item.get("price_usd")
        if pusd is None:
            continue
        try:
            item["price_uah"] = round(float(pusd) * uah_per_usd, 2)
        except (TypeError, ValueError):
            pass


# ---------------------------------------------------------------------------
# Timestamp normalisation
# ---------------------------------------------------------------------------

def normalize_utc_iso_string(value: Any) -> Optional[str]:
    """
    Parse an ISO-like timestamp and return UTC ISO-8601 with trailing ``Z``.

    Ensures the browser always receives an unambiguous instant (avoids mixing
    naive local vs Z/+00:00 parsing between tabs).
    """
    if value is None:
        return None
    if isinstance(value, datetime):
        dt = value
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        else:
            dt = dt.astimezone(timezone.utc)
        return dt.strftime("%Y-%m-%dT%H:%M:%S") + "Z"

    s = str(value).strip()
    if not s or s.lower() in ("none", "null"):
        return None
    try:
        if len(s) >= 11 and s[10] == " ":
            s = s[:10] + "T" + s[11:]
        if s.endswith("Z") or s.endswith("z"):
            s = s[:-1] + "+00:00"
        dt = datetime.fromisoformat(s)
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        else:
            dt = dt.astimezone(timezone.utc)
        return dt.strftime("%Y-%m-%dT%H:%M:%S") + "Z"
    except (ValueError, TypeError, OSError):
        return s


# ---------------------------------------------------------------------------
# Live-rate fetching
# ---------------------------------------------------------------------------

def fetch_live_rates(
    proxy_url: str,
    rates_path: str,
    timeout: float,
) -> Tuple[Optional[list], Optional[str], Optional[str]]:
    """
    Return ``(rates_list, fetched_at_iso, error_message)``.

    On success ``error_message`` is None; on failure ``rates_list`` is None.
    """
    url = proxy_url + rates_path
    try:
        resp = requests.get(url, timeout=timeout)
        resp.raise_for_status()
        data = resp.json()
    except (requests.RequestException, ValueError) as exc:
        LOG.warning("live rates fetch failed: %s", exc)
        return None, None, str(exc)

    rates = data.get("rates")
    if not isinstance(rates, list):
        return None, None, "Invalid proxy payload: rates is not a list"

    enrich_rates_with_crypto_uah(rates)
    fetched = data.get("fetched_at")
    fetched_s = normalize_utc_iso_string(fetched) if fetched is not None else None
    return rates, fetched_s, None
