#!/usr/bin/env python3
"""
RabbitMQ consumer for market_events.

It persists market and price snapshots into PostgreSQL. The consumer is
intentionally defensive: a dead PostgreSQL connection should reconnect, and a
single malformed message must not block the whole queue forever.
"""
import json
import logging
import os
import time

import pika
import psycopg2

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
)
log = logging.getLogger(__name__)

RABBITMQ_URL = os.environ["RABBITMQ_URL"]
DATABASE_URL = os.environ["DATABASE_URL"]
QUEUE_NAME = "market_events"
DEAD_QUEUE_NAME = "market_events_dead_letter"

INSERT_SQL = """
    INSERT INTO market_snapshots
        (question, slug, yes_price, no_price, volume_24h, category, end_date, fetched_at)
    VALUES
        (%(question)s, %(slug)s, %(yes_price)s, %(no_price)s,
         %(volume_24h)s, %(category)s, %(end_date)s, %(fetched_at)s)
    ON CONFLICT (slug, fetched_at) DO NOTHING
"""

INSERT_PRICE_SQL = """
    INSERT INTO price_snapshots
        (coin, price_usd, change_24h, fetched_at)
    VALUES
        (%(coin)s, %(price_usd)s, %(change_24h)s, %(fetched_at)s)
    ON CONFLICT (coin, fetched_at) DO NOTHING
"""


def connect_postgres() -> psycopg2.extensions.connection:
    while True:
        try:
            conn = psycopg2.connect(DATABASE_URL)
            log.info("Connected to PostgreSQL")
            return conn
        except Exception as exc:
            log.error("PostgreSQL unavailable: %s - retrying in 5s", exc)
            time.sleep(5)


def reconnect_postgres(old_conn=None) -> psycopg2.extensions.connection:
    if old_conn is not None:
        try:
            old_conn.close()
        except Exception:
            pass
    return connect_postgres()


def init_schema(conn: psycopg2.extensions.connection) -> None:
    schema_path = os.path.join(os.path.dirname(__file__), "schema.sql")
    with open(schema_path) as f:
        ddl = f.read()
    with conn.cursor() as cur:
        cur.execute(ddl)
    conn.commit()
    log.info("Schema initialized")


def connect_rabbitmq() -> pika.BlockingConnection:
    while True:
        try:
            params = pika.URLParameters(RABBITMQ_URL)
            conn = pika.BlockingConnection(params)
            log.info("Connected to RabbitMQ")
            return conn
        except Exception as exc:
            log.error("RabbitMQ unavailable: %s - retrying in 5s", exc)
            time.sleep(5)


def execute_with_reconnect(db_ref: dict, sql: str, row: dict) -> None:
    for attempt in range(2):
        db = db_ref["conn"]
        try:
            with db.cursor() as cur:
                cur.execute(sql, row)
            db.commit()
            return
        except (psycopg2.OperationalError, psycopg2.InterfaceError):
            log.warning("PostgreSQL connection dropped; reconnecting")
            try:
                db.rollback()
            except Exception:
                pass
            db_ref["conn"] = reconnect_postgres(db)
            if attempt == 1:
                raise


def send_to_dead_letter(ch, body: bytes) -> None:
    ch.basic_publish(
        exchange="",
        routing_key=DEAD_QUEUE_NAME,
        body=body,
        properties=pika.BasicProperties(delivery_mode=2),
    )


def make_callback(db_ref: dict):
    def callback(ch, method, properties, body):
        try:
            data = json.loads(body)
            msg_type = data.get("type", "market")

            if msg_type == "price":
                row = {
                    "coin": data.get("coin"),
                    "price_usd": data.get("price_usd"),
                    "change_24h": data.get("change_24h"),
                    "fetched_at": data.get("fetched_at"),
                }
                execute_with_reconnect(db_ref, INSERT_PRICE_SQL, row)
                ch.basic_ack(delivery_tag=method.delivery_tag)
                log.info("Stored price: %s $%.2f", data.get("coin"), data.get("price_usd", 0))
                return

            row = {
                "question": data.get("question"),
                "slug": data.get("slug"),
                "yes_price": data.get("yes_price"),
                "no_price": data.get("no_price"),
                "volume_24h": data.get("volume_24h"),
                "category": data.get("category"),
                "end_date": data.get("end_date") or None,
                "fetched_at": data.get("fetched_at"),
            }
            execute_with_reconnect(db_ref, INSERT_SQL, row)
            ch.basic_ack(delivery_tag=method.delivery_tag)
            log.info("Stored snapshot: %s", data.get("slug"))
        except (psycopg2.OperationalError, psycopg2.InterfaceError) as exc:
            log.error("Database unavailable while processing message: %s", exc)
            ch.basic_nack(delivery_tag=method.delivery_tag, requeue=True)
            raise
        except Exception as exc:
            log.error("Failed to process message; moving to dead-letter queue: %s", exc)
            try:
                db_ref["conn"].rollback()
            except Exception:
                pass
            try:
                send_to_dead_letter(ch, body)
            except Exception as dead_exc:
                log.error("Dead-letter publish failed: %s", dead_exc)
                ch.basic_nack(delivery_tag=method.delivery_tag, requeue=True)
                raise
            ch.basic_ack(delivery_tag=method.delivery_tag)

    return callback


def main() -> None:
    db = connect_postgres()
    init_schema(db)
    db_ref = {"conn": db}

    while True:
        try:
            mq = connect_rabbitmq()
            channel = mq.channel()
            channel.queue_declare(queue=QUEUE_NAME, durable=True)
            channel.queue_declare(queue=DEAD_QUEUE_NAME, durable=True)
            channel.basic_qos(prefetch_count=1)
            channel.basic_consume(
                queue=QUEUE_NAME,
                on_message_callback=make_callback(db_ref),
            )
            log.info("Consuming from %s", QUEUE_NAME)
            channel.start_consuming()
        except Exception as exc:
            log.error("Consumer loop error: %s - reconnecting", exc)
            time.sleep(5)
            db_ref["conn"] = reconnect_postgres(db_ref.get("conn"))


if __name__ == "__main__":
    main()
