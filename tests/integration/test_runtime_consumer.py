import json
from datetime import datetime, timezone


def _enqueue_event(runtime_db_conn, payload: dict) -> int:
    with runtime_db_conn.cursor() as cur:
        cur.execute("SELECT runtime.enqueue_event(%s::jsonb)", (json.dumps(payload),))
        return int(cur.fetchone()[0])


def _count_rows(db_conn, table_name: str) -> int:
    with db_conn.cursor() as cur:
        cur.execute(f"SELECT COUNT(*) AS count FROM {table_name}")
        return int(cur.fetchone()["count"])


def test_runtime_consumer_persists_market_events_from_runtime_queue(
    runtime_consumer_module,
    runtime_db_conn,
    db_conn,
):
    msg_id = _enqueue_event(
        runtime_db_conn,
        {
            "question": "Will BTC reach 100k?",
            "slug": "btc-100k",
            "yes_price": 0.61,
            "no_price": 0.39,
            "volume_24h": 1200.0,
            "category": "crypto",
            "end_date": None,
            "fetched_at": datetime(2026, 4, 23, 12, 0, tzinfo=timezone.utc).isoformat(),
        },
    )

    processed = runtime_consumer_module.drain_batch(runtime_db_conn)

    with db_conn.cursor() as cur:
        cur.execute("SELECT slug, yes_price FROM market_snapshots")
        saved = cur.fetchone()
        cur.execute("SELECT COUNT(*) AS count FROM runtime.event_retry WHERE msg_id = %s", (msg_id,))
        retry_rows = cur.fetchone()["count"]

    assert processed == 1
    assert saved["slug"] == "btc-100k"
    assert float(saved["yes_price"]) == 0.61
    assert retry_rows == 0


def test_runtime_consumer_persists_price_events_from_runtime_queue(
    runtime_consumer_module,
    runtime_db_conn,
    db_conn,
):
    msg_id = _enqueue_event(
        runtime_db_conn,
        {
            "type": "price",
            "coin": "bitcoin",
            "price_usd": 97000.0,
            "change_24h": -1.2,
            "fetched_at": datetime(2026, 4, 23, 12, 0, tzinfo=timezone.utc).isoformat(),
        },
    )

    processed = runtime_consumer_module.drain_batch(runtime_db_conn)

    with db_conn.cursor() as cur:
        cur.execute("SELECT coin, price_usd FROM price_snapshots")
        saved = cur.fetchone()
        cur.execute("SELECT COUNT(*) AS count FROM runtime.event_retry WHERE msg_id = %s", (msg_id,))
        retry_rows = cur.fetchone()["count"]

    assert processed == 1
    assert saved["coin"] == "bitcoin"
    assert float(saved["price_usd"]) == 97000.0
    assert retry_rows == 0


def test_runtime_consumer_queue_writes_are_idempotent(
    runtime_consumer_module,
    runtime_db_conn,
    db_conn,
):
    payload = {
        "question": "Will BTC reach 100k?",
        "slug": "btc-100k",
        "yes_price": 0.61,
        "no_price": 0.39,
        "volume_24h": 1200.0,
        "category": "crypto",
        "end_date": None,
        "fetched_at": datetime(2026, 4, 23, 12, 0, tzinfo=timezone.utc).isoformat(),
    }

    _enqueue_event(runtime_db_conn, payload)
    _enqueue_event(runtime_db_conn, payload)

    processed = runtime_consumer_module.drain_batch(runtime_db_conn)

    assert processed == 2
    assert _count_rows(db_conn, "market_snapshots") == 1
    assert _count_rows(db_conn, "runtime.event_retry") == 0


def test_runtime_consumer_sends_invalid_market_events_to_dlq(
    runtime_consumer_module,
    runtime_db_conn,
    db_conn,
    monkeypatch,
):
    monkeypatch.setattr(runtime_consumer_module, "MAX_RETRIES", 1)
    msg_id = _enqueue_event(
        runtime_db_conn,
        {
            "question": None,
            "slug": "btc-100k",
            "yes_price": 0.61,
            "no_price": 0.39,
            "volume_24h": 1200.0,
            "category": "crypto",
            "end_date": None,
            "fetched_at": datetime(2026, 4, 23, 12, 0, tzinfo=timezone.utc).isoformat(),
        },
    )

    processed = runtime_consumer_module.drain_batch(runtime_db_conn)

    with db_conn.cursor() as cur:
        cur.execute(
            """
            SELECT original_msg_id, dlq_msg_id, attempt_count, payload, last_error
            FROM runtime.dead_letter_audit
            WHERE original_msg_id = %s
            """,
            (msg_id,),
        )
        audit_row = cur.fetchone()

    assert processed == 0
    assert audit_row["original_msg_id"] == msg_id
    assert audit_row["dlq_msg_id"] is not None
    assert audit_row["attempt_count"] == 1
    assert audit_row["payload"]["slug"] == "btc-100k"
    assert audit_row["last_error"]
    assert _count_rows(db_conn, "market_snapshots") == 0
    assert _count_rows(db_conn, "runtime.event_retry") == 0
