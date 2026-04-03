"""Flask HTTP API for historical data."""

from __future__ import annotations

import logging
from datetime import datetime, timezone
from typing import Any, Optional

from flask import Flask, Response, jsonify, request

from config import HistoryConfig
from repository import (
    build_dashboard_items,
    fetch_history_rows,
    fetch_series_for_range,
    metric_for_asset_type,
    parse_asset_pairs,
)

LOG = logging.getLogger("coinops.history.app")


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
            return jsonify({
                "items": rows,
                "count": len(rows),
                "generated_at": datetime.now(timezone.utc).isoformat(),
            })
        except Exception as exc:
            LOG.exception("history query failed: %s", exc)
            return jsonify({"error": "history_query_failed", "detail": str(exc)}), 500

    @app.get("/api/v1/history/series")
    def history_series() -> Any:
        symbol = (request.args.get("asset_symbol") or "").strip().upper()
        asset_type = (request.args.get("asset_type") or "").strip().lower()
        range_key = (request.args.get("range") or "7d").strip()
        date_from = (request.args.get("date_from") or "").strip() or None
        date_to = (request.args.get("date_to") or "").strip() or None
        if not symbol or asset_type not in ("fiat", "crypto"):
            return jsonify({
                "error": "invalid_params",
                "detail": "asset_symbol and asset_type (fiat|crypto) required",
            }), 400
        try:
            rows = fetch_series_for_range(
                cfg, symbol, asset_type, range_key, date_from=date_from, date_to=date_to,
            )
            return jsonify({
                "asset_symbol": symbol,
                "asset_type": asset_type,
                "range": range_key,
                "series_metric": metric_for_asset_type(asset_type),
                "items": rows,
                "count": len(rows),
                "generated_at": datetime.now(timezone.utc).isoformat(),
            })
        except Exception as exc:
            LOG.exception("history series failed: %s", exc)
            return jsonify({"error": "history_series_failed", "detail": str(exc)}), 500

    @app.get("/api/v1/history/dashboard")
    def history_dashboard() -> Any:
        pairs_raw = request.args.get("pairs") or ""
        pairs = parse_asset_pairs(pairs_raw)
        if not pairs:
            return jsonify({
                "error": "invalid_params",
                "detail": "pairs=USD:fiat,EUR:fiat,... required",
            }), 400
        if len(pairs) > 80:
            return jsonify({"error": "invalid_params", "detail": "too many pairs (max 80)"}), 400
        try:
            items = build_dashboard_items(cfg, pairs)
            return jsonify({
                "items": items,
                "count": len(items),
                "generated_at": datetime.now(timezone.utc).isoformat(),
            })
        except Exception as exc:
            LOG.exception("history dashboard failed: %s", exc)
            return jsonify({"error": "history_dashboard_failed", "detail": str(exc)}), 500

    return app


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
