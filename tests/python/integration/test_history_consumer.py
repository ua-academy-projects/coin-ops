import json
from datetime import datetime, timezone
from types import SimpleNamespace

import pytest


class ChannelSpy:
    def __init__(self):
        self.acks = []
        self.nacks = []
        self.published = []

    def basic_ack(self, delivery_tag):
        self.acks.append(delivery_tag)

    def basic_nack(self, delivery_tag, requeue):
        self.nacks.append((delivery_tag, requeue))

    def basic_publish(self, *args, **kwargs):
        self.published.append((args, kwargs))


def _count_rows(db_conn, table_name: str) -> int:
    with db_conn.cursor() as cur:
        cur.execute(f"SELECT COUNT(*) AS count FROM {table_name}")
        return int(cur.fetchone()["count"])


def test_init_schema_creates_expected_tables(history_consumer_module, db_conn):
    with db_conn.cursor() as cur:
        cur.execute("DROP TABLE IF EXISTS whale_positions CASCADE")
        cur.execute("DROP TABLE IF EXISTS whales CASCADE")
        cur.execute("DROP TABLE IF EXISTS market_snapshots CASCADE")
        cur.execute("DROP TABLE IF EXISTS price_snapshots CASCADE")
    db_conn.commit()

    history_consumer_module.init_schema(db_conn)

    with db_conn.cursor() as cur:
        cur.execute("SELECT to_regclass('public.market_snapshots') AS market_snapshots")
        market_table = cur.fetchone()["market_snapshots"]
        cur.execute("SELECT to_regclass('public.price_snapshots') AS price_snapshots")
        price_table = cur.fetchone()["price_snapshots"]

    assert market_table == "market_snapshots"
    assert price_table == "price_snapshots"


def test_market_snapshot_persisted_via_execute_with_reconnect(history_consumer_module, db_conn):
    db_ref = {"conn": db_conn}
    row = {
        "question": "Will BTC reach 100k?",
        "slug": "btc-100k",
        "yes_price": 0.61,
        "no_price": 0.39,
        "volume_24h": 1200.0,
        "category": "crypto",
        "end_date": None,
        "fetched_at": datetime(2026, 4, 23, 12, 0, tzinfo=timezone.utc),
    }

    history_consumer_module.execute_with_reconnect(db_ref, history_consumer_module.INSERT_SQL, row)

    with db_conn.cursor() as cur:
        cur.execute("SELECT slug, yes_price FROM market_snapshots")
        saved = cur.fetchone()

    assert saved["slug"] == "btc-100k"
    assert float(saved["yes_price"]) == 0.61


def test_price_snapshot_persisted_via_execute_with_reconnect(history_consumer_module, db_conn):
    db_ref = {"conn": db_conn}
    row = {
        "coin": "bitcoin",
        "price_usd": 97000.0,
        "change_24h": -1.2,
        "fetched_at": datetime(2026, 4, 23, 12, 0, tzinfo=timezone.utc),
    }

    history_consumer_module.execute_with_reconnect(
        db_ref,
        history_consumer_module.INSERT_PRICE_SQL,
        row,
    )

    with db_conn.cursor() as cur:
        cur.execute("SELECT coin, price_usd FROM price_snapshots")
        saved = cur.fetchone()

    assert saved["coin"] == "bitcoin"
    assert float(saved["price_usd"]) == 97000.0


def test_duplicate_market_insert_is_idempotent(history_consumer_module, db_conn):
    db_ref = {"conn": db_conn}
    row = {
        "question": "Will BTC reach 100k?",
        "slug": "btc-100k",
        "yes_price": 0.61,
        "no_price": 0.39,
        "volume_24h": 1200.0,
        "category": "crypto",
        "end_date": None,
        "fetched_at": datetime(2026, 4, 23, 12, 0, tzinfo=timezone.utc),
    }

    history_consumer_module.execute_with_reconnect(db_ref, history_consumer_module.INSERT_SQL, row)
    history_consumer_module.execute_with_reconnect(db_ref, history_consumer_module.INSERT_SQL, row)

    assert _count_rows(db_conn, "market_snapshots") == 1


def test_duplicate_price_insert_is_idempotent(history_consumer_module, db_conn):
    db_ref = {"conn": db_conn}
    row = {
        "coin": "bitcoin",
        "price_usd": 97000.0,
        "change_24h": -1.2,
        "fetched_at": datetime(2026, 4, 23, 12, 0, tzinfo=timezone.utc),
    }

    history_consumer_module.execute_with_reconnect(
        db_ref,
        history_consumer_module.INSERT_PRICE_SQL,
        row,
    )
    history_consumer_module.execute_with_reconnect(
        db_ref,
        history_consumer_module.INSERT_PRICE_SQL,
        row,
    )

    assert _count_rows(db_conn, "price_snapshots") == 1


def test_callback_persists_market_message_to_real_db(history_consumer_module, db_conn):
    db_ref = {"conn": db_conn}
    callback = history_consumer_module.make_callback(db_ref)
    channel = ChannelSpy()
    body = json.dumps(
        {
            "question": "Will BTC reach 100k?",
            "slug": "btc-100k",
            "yes_price": 0.61,
            "no_price": 0.39,
            "volume_24h": 1200.0,
            "category": "crypto",
            "end_date": "",
            "fetched_at": "2026-04-23T12:00:00Z",
        }
    ).encode()

    callback(channel, SimpleNamespace(delivery_tag=11), None, body)

    assert channel.acks == [11]
    assert channel.nacks == []
    assert _count_rows(db_conn, "market_snapshots") == 1


def test_callback_persists_price_message_to_real_db(history_consumer_module, db_conn):
    db_ref = {"conn": db_conn}
    callback = history_consumer_module.make_callback(db_ref)
    channel = ChannelSpy()
    body = json.dumps(
        {
            "type": "price",
            "coin": "bitcoin",
            "price_usd": 97000.0,
            "change_24h": -1.2,
            "fetched_at": "2026-04-23T12:00:00Z",
        }
    ).encode()

    callback(channel, SimpleNamespace(delivery_tag=12), None, body)

    assert channel.acks == [12]
    assert channel.nacks == []
    assert _count_rows(db_conn, "price_snapshots") == 1


def test_null_required_field_raises_integrity_error(history_consumer_module, db_conn):
    db_ref = {"conn": db_conn}
    invalid_row = {
        "question": None,
        "slug": "btc-100k",
        "yes_price": 0.61,
        "no_price": 0.39,
        "volume_24h": 1200.0,
        "category": "crypto",
        "end_date": None,
        "fetched_at": datetime(2026, 4, 23, 12, 0, tzinfo=timezone.utc),
    }

    with pytest.raises(history_consumer_module.psycopg2.IntegrityError):
        history_consumer_module.execute_with_reconnect(
            db_ref,
            history_consumer_module.INSERT_SQL,
            invalid_row,
        )
