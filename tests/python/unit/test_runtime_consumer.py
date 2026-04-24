import json

import pytest

from tests.python._helpers import ConnectionSpy, description_from_names


def test_process_message_routes_market_payload_and_acks(runtime_consumer_module):
    conn = ConnectionSpy()

    runtime_consumer_module.process_message(
        conn,
        101,
        {
            "question": "Will BTC reach 100k?",
            "slug": "btc-100k",
            "yes_price": 0.61,
            "no_price": 0.39,
            "volume_24h": 1234,
            "category": "crypto",
            "end_date": "",
            "fetched_at": "2026-04-23T12:00:00Z",
        },
    )

    insert_sql, row = conn.cursor_obj.executed[0]
    ack_sql, ack_params = conn.cursor_obj.executed[1]
    assert insert_sql == runtime_consumer_module.INSERT_MARKET
    assert row["slug"] == "btc-100k"
    assert row["end_date"] is None
    assert ack_sql == runtime_consumer_module.SQL_ACK
    assert ack_params == (101,)


def test_process_message_routes_price_payload_and_acks(runtime_consumer_module):
    conn = ConnectionSpy()

    runtime_consumer_module.process_message(
        conn,
        102,
        {
            "type": "price",
            "coin": "bitcoin",
            "price_usd": 97000.0,
            "change_24h": -1.2,
            "fetched_at": "2026-04-23T12:00:00Z",
        },
    )

    insert_sql, row = conn.cursor_obj.executed[0]
    ack_sql, ack_params = conn.cursor_obj.executed[1]
    assert insert_sql == runtime_consumer_module.INSERT_PRICE
    assert row["coin"] == "bitcoin"
    assert row["price_usd"] == 97000.0
    assert ack_sql == runtime_consumer_module.SQL_ACK
    assert ack_params == (102,)


def test_drain_batch_decodes_string_payloads(runtime_consumer_module, monkeypatch):
    payload = {
        "type": "price",
        "coin": "bitcoin",
        "price_usd": 97000.0,
        "change_24h": -1.2,
        "fetched_at": "2026-04-23T12:00:00Z",
    }
    conn = ConnectionSpy(
        rows=[(201, 0, None, None, json.dumps(payload))],
        description=description_from_names("msg_id", "read_ct", "enqueued_at", "vt", "message"),
    )
    seen = []
    monkeypatch.setattr(
        runtime_consumer_module,
        "process_message",
        lambda conn, msg_id, payload: seen.append((msg_id, payload)),
    )

    processed = runtime_consumer_module.drain_batch(conn)

    sql, params = conn.cursor_obj.executed[0]
    assert processed == 1
    assert seen == [(201, payload)]
    assert sql == runtime_consumer_module.SQL_CLAIM
    assert params == (
        runtime_consumer_module.BATCH_SIZE,
        runtime_consumer_module.VT_SECONDS,
    )


def test_drain_batch_sends_malformed_json_to_fail_path(runtime_consumer_module, monkeypatch):
    conn = ConnectionSpy(
        rows=[(202, 0, None, None, "{not-json")],
        description=description_from_names("msg_id", "read_ct", "enqueued_at", "vt", "message"),
    )
    failures = []
    monkeypatch.setattr(
        runtime_consumer_module,
        "process_message",
        lambda *args, **kwargs: pytest.fail("process_message should not run for malformed JSON"),
    )
    monkeypatch.setattr(
        runtime_consumer_module,
        "handle_failure",
        lambda conn, msg_id, error: failures.append((msg_id, error)),
    )

    processed = runtime_consumer_module.drain_batch(conn)

    assert processed == 0
    assert failures[0][0] == 202
    assert "JSONDecodeError" in failures[0][1]


def test_drain_batch_reports_processing_failures(runtime_consumer_module, monkeypatch):
    conn = ConnectionSpy(
        rows=[(203, 0, None, None, {"slug": "btc-100k", "yes_price": 0.61})],
        description=description_from_names("msg_id", "read_ct", "enqueued_at", "vt", "message"),
    )
    failures = []

    def raise_processing_error(conn, msg_id, payload):
        raise ValueError("boom")

    monkeypatch.setattr(runtime_consumer_module, "process_message", raise_processing_error)
    monkeypatch.setattr(
        runtime_consumer_module,
        "handle_failure",
        lambda conn, msg_id, error: failures.append((msg_id, error)),
    )

    processed = runtime_consumer_module.drain_batch(conn)

    assert processed == 0
    assert failures == [(203, "boom")]
