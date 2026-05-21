import pytest

from tests.python._helpers import ConnectionSpy


def test_get_history_without_category_uses_recent_query(history_main_module, monkeypatch):
    conn = ConnectionSpy(rows=[{"id": 1, "slug": "btc-100k", "category": "crypto"}])
    monkeypatch.setattr(history_main_module, "get_db", lambda: conn)

    result = history_main_module.get_history(limit=3, category=None)

    sql, params = conn.cursor_obj.executed[0]
    assert result == [{"id": 1, "slug": "btc-100k", "category": "crypto"}]
    assert "FROM market_snapshots" in sql
    assert "WHERE category ILIKE %s" not in sql
    assert params == (3,)
    assert conn.closed is True


def test_get_history_with_category_uses_ilike_filter(history_main_module, monkeypatch):
    conn = ConnectionSpy(rows=[{"id": 2, "slug": "sports-bet", "category": "sports"}])
    monkeypatch.setattr(history_main_module, "get_db", lambda: conn)

    result = history_main_module.get_history(limit=5, category="sports")

    sql, params = conn.cursor_obj.executed[0]
    assert result == [{"id": 2, "slug": "sports-bet", "category": "sports"}]
    assert "WHERE category ILIKE %s" in sql
    assert params == ("%sports%", 5)
    assert conn.closed is True


def test_get_market_history_raises_404_when_market_missing(history_main_module, monkeypatch):
    conn = ConnectionSpy(rows=[])
    monkeypatch.setattr(history_main_module, "get_db", lambda: conn)

    with pytest.raises(history_main_module.HTTPException) as exc:
        history_main_module.get_market_history("missing-market", limit=10)

    assert exc.value.status_code == 404
    assert exc.value.detail == "Market not found"
    assert conn.closed is True


def test_get_price_history_uses_coin_filter_and_serializes_rows(history_main_module, monkeypatch):
    conn = ConnectionSpy(
        rows=[
            {
                "fetched_at": "2026-04-23T12:00:00Z",
                "coin": "bitcoin",
                "price_usd": 97000.0,
                "change_24h": -1.2,
            }
        ]
    )
    monkeypatch.setattr(history_main_module, "get_db", lambda: conn)

    result = history_main_module.get_price_history("bitcoin", limit=72)

    sql, params = conn.cursor_obj.executed[0]
    assert result == [
        {
            "fetched_at": "2026-04-23T12:00:00Z",
            "coin": "bitcoin",
            "price_usd": 97000.0,
            "change_24h": -1.2,
        }
    ]
    assert "FROM price_snapshots" in sql
    assert "WHERE coin = %s" in sql
    assert params == ("bitcoin", 72)
    assert conn.closed is True
