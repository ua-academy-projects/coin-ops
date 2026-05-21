from datetime import datetime, timezone


def _insert_market(
    db_conn,
    slug: str,
    category: str,
    fetched_at: datetime,
    question: str = "Will BTC hit 100k?",
):
    with db_conn.cursor() as cur:
        cur.execute(
            """
            INSERT INTO market_snapshots
                (question, slug, yes_price, no_price, volume_24h, category, end_date, fetched_at)
            VALUES
                (%s, %s, %s, %s, %s, %s, %s, %s)
            """,
            (
                question,
                slug,
                0.61,
                0.39,
                1200.0,
                category,
                None,
                fetched_at,
            ),
        )
    db_conn.commit()


def _insert_price(db_conn, coin: str, price_usd: float, fetched_at: datetime):
    with db_conn.cursor() as cur:
        cur.execute(
            """
            INSERT INTO price_snapshots
                (coin, price_usd, change_24h, fetched_at)
            VALUES
                (%s, %s, %s, %s)
            """,
            (coin, price_usd, -1.2, fetched_at),
        )
    db_conn.commit()


def test_health_returns_ok(api_client):
    response = api_client.get("/health")

    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_get_history_returns_inserted_snapshots(api_client, db_conn):
    _insert_market(
        db_conn,
        slug="btc-100k",
        category="crypto",
        fetched_at=datetime(2026, 4, 23, 12, 0, tzinfo=timezone.utc),
    )

    response = api_client.get("/history?limit=10")
    body = response.json()

    assert response.status_code == 200
    assert len(body) == 1
    assert body[0]["slug"] == "btc-100k"
    assert body[0]["category"] == "crypto"


def test_get_history_respects_limit_parameter(api_client, db_conn):
    _insert_market(
        db_conn,
        slug="market-1",
        category="crypto",
        fetched_at=datetime(2026, 4, 23, 12, 0, tzinfo=timezone.utc),
    )
    _insert_market(
        db_conn,
        slug="market-2",
        category="crypto",
        fetched_at=datetime(2026, 4, 23, 12, 1, tzinfo=timezone.utc),
    )
    _insert_market(
        db_conn,
        slug="market-3",
        category="crypto",
        fetched_at=datetime(2026, 4, 23, 12, 2, tzinfo=timezone.utc),
    )

    response = api_client.get("/history?limit=2")
    body = response.json()

    assert response.status_code == 200
    assert len(body) == 2
    assert [row["slug"] for row in body] == ["market-3", "market-2"]


def test_get_history_filters_by_category(api_client, db_conn):
    _insert_market(
        db_conn,
        slug="sports-1",
        category="sports",
        fetched_at=datetime(2026, 4, 23, 12, 0, tzinfo=timezone.utc),
    )
    _insert_market(
        db_conn,
        slug="crypto-1",
        category="crypto",
        fetched_at=datetime(2026, 4, 23, 12, 1, tzinfo=timezone.utc),
    )

    # Query uses a different case to verify ILIKE behavior.
    response = api_client.get("/history?limit=10&category=Sport")
    body = response.json()

    assert response.status_code == 200
    assert len(body) == 1
    assert body[0]["slug"] == "sports-1"


def test_get_market_history_returns_slug_time_series(api_client, db_conn):
    _insert_market(
        db_conn,
        slug="btc-100k",
        category="crypto",
        fetched_at=datetime(2026, 4, 23, 11, 59, tzinfo=timezone.utc),
    )
    _insert_market(
        db_conn,
        slug="btc-100k",
        category="crypto",
        fetched_at=datetime(2026, 4, 23, 12, 0, tzinfo=timezone.utc),
    )
    _insert_market(
        db_conn,
        slug="eth-5k",
        category="crypto",
        fetched_at=datetime(2026, 4, 23, 12, 1, tzinfo=timezone.utc),
    )

    response = api_client.get("/history/btc-100k?limit=10")
    body = response.json()

    assert response.status_code == 200
    assert len(body) == 2
    assert all("yes_price" in row for row in body)


def test_get_market_history_returns_404_for_missing_slug(api_client):
    response = api_client.get("/history/missing?limit=10")

    assert response.status_code == 404
    assert response.json()["detail"] == "Market not found"


def test_get_price_history_returns_coin_data(api_client, db_conn):
    _insert_price(
        db_conn,
        coin="bitcoin",
        price_usd=97000.0,
        fetched_at=datetime(2026, 4, 23, 12, 0, tzinfo=timezone.utc),
    )
    _insert_price(
        db_conn,
        coin="ethereum",
        price_usd=4900.0,
        fetched_at=datetime(2026, 4, 23, 12, 1, tzinfo=timezone.utc),
    )

    response = api_client.get("/prices/history/bitcoin?limit=50")
    body = response.json()

    assert response.status_code == 200
    assert len(body) == 1
    assert body[0]["coin"] == "bitcoin"
    assert body[0]["price_usd"] == 97000.0


def test_get_price_history_returns_404_for_unknown_coin(api_client):
    response = api_client.get("/prices/history/doge?limit=50")

    assert response.status_code == 404
    assert response.json()["detail"] == "No price data for this coin"
