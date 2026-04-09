#!/usr/bin/python3

"""
CoinOps Flask UI.

Serves a single page with two tabs:
- live rates from the Go proxy
- historical analytics via the History Service API (no direct DB access)
"""

from __future__ import annotations

import logging
import os
from dataclasses import dataclass
from datetime import date
from typing import Any, Optional

import requests
import state_store
from flask import Flask, jsonify, render_template, request
from flask_limiter import Limiter
from flask_limiter.util import get_remote_address
from helpers import fetch_live_rates

LOG = logging.getLogger("coinops.frontend")


def history_base_url_from_environ() -> str:
    """
    Base URL of the History Service (scheme + host[:port]), without path.

    Supports either:
    - HISTORY_BASE_URL=http://host:8090
    - HISTORY_API_URL=http://host:8090/api/v1/history (legacy full path — suffix stripped)

    Raises ValueError if neither is set (fail-fast).
    """
    explicit = os.environ.get("HISTORY_BASE_URL", "").strip()
    if explicit:
        return explicit.rstrip("/")
    raw = os.environ.get("HISTORY_API_URL", "").strip().rstrip("/")
    if not raw:
        raise ValueError("HISTORY_BASE_URL or HISTORY_API_URL environment variable is required but not set")
    for suffix in ("/api/v1/history", "/v1/history"):
        if raw.endswith(suffix):
            return raw[: -len(suffix)].rstrip("/")
    return raw


@dataclass(frozen=True)
class AppConfig:
    """Flask app configuration from the environment."""

    proxy_base_url: str
    rates_path: str
    history_base_url: str
    http_timeout: float

    @property
    def history_list_url(self) -> str:
        return f"{self.history_base_url}/api/v1/history"

    @property
    def history_series_url(self) -> str:
        return f"{self.history_base_url}/api/v1/history/series"

    @property
    def history_dashboard_url(self) -> str:
        return f"{self.history_base_url}/api/v1/history/dashboard"

    @classmethod
    def from_environ(cls) -> "AppConfig":
        proxy = os.environ.get("PROXY_URL", "").strip().rstrip("/")
        if not proxy:
            raise ValueError("PROXY_URL environment variable is required but not set")
        path = os.environ.get("COINOPS_RATES_PATH", "/api/v1/rates")
        if not path.startswith("/"):
            path = "/" + path
        base = history_base_url_from_environ()
        timeout = float(os.environ.get("COINOPS_HTTP_TIMEOUT", "15"))
        return cls(
            proxy_base_url=proxy,
            rates_path=path,
            history_base_url=base,
            http_timeout=timeout,
        )


# ---------------------------------------------------------------------------
# Shared proxy helper (DRY for history endpoints)
# ---------------------------------------------------------------------------

def _proxy_json(url: str, params: dict, timeout: float, label: str):
    """Forward a GET request and return JSON or a 502 error tuple."""
    try:
        resp = requests.get(url, params=params, timeout=timeout)
        resp.raise_for_status()
        return jsonify(resp.json())
    except (requests.RequestException, ValueError) as exc:
        LOG.warning("%s proxy failed: %s", label, exc)
        return jsonify({"error": str(exc), "items": [], "count": 0}), 502


def _ui_state_cookie_response(payload: dict[str, Any], set_sid: Optional[str] = None):
    """JSON response; optionally sets ``coinops_sid`` session cookie."""
    resp = jsonify(payload)
    if set_sid:
        resp.set_cookie(
            "coinops_sid",
            set_sid,
            max_age=60 * 60 * 24 * 365,
            httponly=True,
            samesite="Lax",
            path="/",
        )
    return resp


def create_app() -> Flask:
    """Application factory for tests and ``flask run``."""
    logging.basicConfig(level=logging.INFO)
    cfg = AppConfig.from_environ()
    app = Flask(__name__)
    app.config["COINOPS_CFG"] = cfg

    limiter = Limiter(
        get_remote_address,
        app=app,
        default_limits=["60/minute"],
        storage_uri="memory://",
    )

    @app.after_request
    def set_security_headers(response):
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["X-Frame-Options"] = "DENY"
        response.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"
        response.headers["Permissions-Policy"] = "camera=(), microphone=(), geolocation=()"
        csp = (
            "default-src 'self'; "
            "script-src 'self' https://cdn.jsdelivr.net 'unsafe-inline'; "
            "style-src 'self' https://cdn.jsdelivr.net 'unsafe-inline'; "
            "font-src 'self' https://cdn.jsdelivr.net; "
            "img-src 'self' data:; "
            "connect-src 'self'; "
            "frame-ancestors 'none'"
        )
        response.headers["Content-Security-Policy"] = csp
        return response

    # ------------------------------------------------------------------
    # Routes
    # ------------------------------------------------------------------

    @app.route("/")
    def index() -> str:
        """Render the dashboard with current rates."""
        c: AppConfig = app.config["COINOPS_CFG"]
        live_rates, fetched_at, live_error = fetch_live_rates(
            c.proxy_base_url, c.rates_path, c.http_timeout,
        )
        return render_template(
            "index.html",
            live_rates=live_rates,
            live_fetched_at=fetched_at,
            live_error=live_error,
            now_year=date.today().year,
        )

    @app.route("/api/live")
    @limiter.limit("120/minute")
    def api_live():
        """Same-origin JSON for current rates (refresh without full page reload)."""
        c: AppConfig = app.config["COINOPS_CFG"]
        rates, fetched_at, err = fetch_live_rates(
            c.proxy_base_url, c.rates_path, c.http_timeout,
        )
        if err:
            return jsonify({"error": err, "rates": [], "fetched_at": None}), 502
        return jsonify({"rates": rates or [], "fetched_at": fetched_at})

    @app.route("/api/history")
    @limiter.limit("30/minute")
    def api_history_proxy():
        """Same-origin proxy to History Service list endpoint."""
        c: AppConfig = app.config["COINOPS_CFG"]
        limit = request.args.get("limit", default=50, type=int)
        if limit is None or limit < 1:
            limit = 50
        limit = min(limit, 500)
        params: dict[str, Any] = {"limit": limit}
        sym = request.args.get("asset_symbol")
        typ = request.args.get("asset_type")
        if sym:
            params["asset_symbol"] = sym
        if typ in ("fiat", "crypto"):
            params["asset_type"] = typ
        return _proxy_json(c.history_list_url, params, c.http_timeout, "history")

    @app.route("/api/history/series")
    @limiter.limit("30/minute")
    def api_history_series_proxy():
        c: AppConfig = app.config["COINOPS_CFG"]
        return _proxy_json(
            c.history_series_url, dict(request.args), c.http_timeout, "history series",
        )

    @app.route("/api/history/dashboard")
    @limiter.limit("30/minute")
    def api_history_dashboard_proxy():
        c: AppConfig = app.config["COINOPS_CFG"]
        return _proxy_json(
            c.history_dashboard_url, dict(request.args), c.http_timeout, "history dashboard",
        )

    @app.route("/api/v1/ui-state", methods=["GET"])
    def api_ui_state_get():
        """
        Return optional Redis-backed UI state for this browser session.

        Sets ``coinops_sid`` cookie when missing. If ``REDIS_URL`` is unset or Redis is down,
        returns ``enabled: false`` (client keeps ``localStorage`` only).
        """
        sid = request.cookies.get("coinops_sid", "")
        set_sid: Optional[str] = None
        if not state_store.valid_sid(sid):
            set_sid = state_store.new_session_id()
            sid = set_sid
        if not state_store.redis_ui_enabled():
            return _ui_state_cookie_response({"enabled": False, "state": {}}, set_sid)
        return _ui_state_cookie_response(
            {"enabled": True, "state": state_store.get_ui_state(sid)},
            set_sid,
        )

    @app.route("/api/v1/ui-state", methods=["PUT"])
    @limiter.limit("30/minute")
    def api_ui_state_put():
        """Persist UI state JSON (same shape as ``coinops_ui_v2`` in localStorage)."""
        sid = request.cookies.get("coinops_sid", "")
        if not state_store.valid_sid(sid):
            return (
                jsonify({"error": "missing_session", "detail": "GET /api/v1/ui-state first"}),
                400,
            )
        if not state_store.redis_ui_enabled():
            return jsonify({"error": "redis_unavailable"}), 503
        body = request.get_json(silent=True) or {}
        raw = body.get("state")
        if not isinstance(raw, dict):
            return jsonify({"error": "invalid_body"}), 400
        state_store.set_ui_state(sid, raw)
        return jsonify({"ok": True})

    return app


app = create_app()


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.environ.get("PORT", "5000")))
