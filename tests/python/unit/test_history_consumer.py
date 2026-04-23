import json
from types import SimpleNamespace

import pytest

from conftest import ChannelSpy, ConnectionSpy


def test_market_messages_route_to_market_insert(history_consumer_module, monkeypatch):
    executed = []
    monkeypatch.setattr(
        history_consumer_module,
        "execute_with_reconnect",
        lambda db_ref, sql, row: executed.append((sql, row)),
    )

    channel = ChannelSpy()
    callback = history_consumer_module.make_callback({"conn": ConnectionSpy()})
    body = json.dumps(
        {
            "question": "Will BTC reach 100k?",
            "slug": "btc-100k",
            "yes_price": 0.61,
            "no_price": 0.39,
            "volume_24h": 1234,
            "category": "crypto",
            "end_date": "",
            "fetched_at": "2026-04-23T12:00:00Z",
        }
    ).encode()

    callback(channel, SimpleNamespace(delivery_tag=11), None, body)

    sql, row = executed[0]
    assert sql == history_consumer_module.INSERT_SQL
    assert row["slug"] == "btc-100k"
    assert row["end_date"] is None
    assert channel.acks == [11]
    assert channel.nacks == []


def test_price_messages_route_to_price_insert(history_consumer_module, monkeypatch):
    executed = []
    monkeypatch.setattr(
        history_consumer_module,
        "execute_with_reconnect",
        lambda db_ref, sql, row: executed.append((sql, row)),
    )

    channel = ChannelSpy()
    callback = history_consumer_module.make_callback({"conn": ConnectionSpy()})
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

    sql, row = executed[0]
    assert sql == history_consumer_module.INSERT_PRICE_SQL
    assert row["coin"] == "bitcoin"
    assert row["price_usd"] == 97000.0
    assert channel.acks == [12]
    assert channel.nacks == []


def test_invalid_json_is_dead_lettered_and_acked(history_consumer_module, monkeypatch):
    conn = ConnectionSpy()
    dead_letter_bodies = []
    monkeypatch.setattr(
        history_consumer_module,
        "send_to_dead_letter",
        lambda channel, body: dead_letter_bodies.append(body),
    )

    channel = ChannelSpy()
    callback = history_consumer_module.make_callback({"conn": conn})

    callback(channel, SimpleNamespace(delivery_tag=13), None, b"{not-json")

    assert dead_letter_bodies == [b"{not-json"]
    assert conn.rollback_calls == 1
    assert channel.acks == [13]
    assert channel.nacks == []


def test_database_disconnect_requeues_message(history_consumer_module, monkeypatch):
    def raise_operational_error(*args, **kwargs):
        raise history_consumer_module.psycopg2.OperationalError("db down")

    monkeypatch.setattr(history_consumer_module, "execute_with_reconnect", raise_operational_error)

    channel = ChannelSpy()
    callback = history_consumer_module.make_callback({"conn": ConnectionSpy()})
    body = json.dumps({"slug": "btc-100k", "yes_price": 0.61}).encode()

    with pytest.raises(history_consumer_module.psycopg2.OperationalError):
        callback(channel, SimpleNamespace(delivery_tag=14), None, body)

    assert channel.acks == []
    assert channel.nacks == [(14, True)]


def test_dead_letter_publish_failure_requeues_message(history_consumer_module, monkeypatch):
    def raise_dead_letter_error(*args, **kwargs):
        raise RuntimeError("dlq unavailable")

    monkeypatch.setattr(history_consumer_module, "send_to_dead_letter", raise_dead_letter_error)

    channel = ChannelSpy()
    callback = history_consumer_module.make_callback({"conn": ConnectionSpy()})

    with pytest.raises(RuntimeError):
        callback(channel, SimpleNamespace(delivery_tag=15), None, b"{not-json")

    assert channel.acks == []
    assert channel.nacks == [(15, True)]


def test_execute_with_reconnect_swaps_in_new_connection(history_consumer_module, monkeypatch):
    class ReconnectConnection:
        def __init__(self, error=None):
            self.error = error
            self.rollback_calls = 0
            self.commit_calls = 0
            self.executed = []

        def cursor(self):
            return self

        def execute(self, sql, row):
            self.executed.append((sql, row))
            if self.error is not None:
                error = self.error
                self.error = None
                raise error

        def __enter__(self):
            return self

        def __exit__(self, exc_type, exc, tb):
            return False

        def rollback(self):
            self.rollback_calls += 1

        def commit(self):
            self.commit_calls += 1

    first_conn = ReconnectConnection(
        error=history_consumer_module.psycopg2.OperationalError("connection dropped")
    )
    second_conn = ReconnectConnection()
    db_ref = {"conn": first_conn}

    monkeypatch.setattr(history_consumer_module, "reconnect_postgres", lambda old_conn: second_conn)

    history_consumer_module.execute_with_reconnect(
        db_ref,
        history_consumer_module.INSERT_SQL,
        {"slug": "btc-100k", "yes_price": 0.61},
    )

    assert first_conn.rollback_calls == 1
    assert second_conn.executed == [
        (
            history_consumer_module.INSERT_SQL,
            {"slug": "btc-100k", "yes_price": 0.61},
        )
    ]
    assert second_conn.commit_calls == 1
    assert db_ref["conn"] is second_conn
