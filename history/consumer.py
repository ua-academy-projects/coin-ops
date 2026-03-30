#!/usr/bin/env python3
"""
history-consumer — RabbitMQ consumer for market_events queue.
Inserts each market snapshot into PostgreSQL.
Runs as a systemd service (history-consumer.service) on node-01.
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
QUEUE_NAME   = "market_events"

INSERT_SQL = """
    INSERT INTO market_snapshots
        (question, slug, yes_price, no_price, volume_24h, category, end_date, fetched_at)
    VALUES
        (%(question)s, %(slug)s, %(yes_price)s, %(no_price)s,
         %(volume_24h)s, %(category)s, %(end_date)s, %(fetched_at)s)
    ON CONFLICT (slug, fetched_at) DO NOTHING
"""


def connect_postgres() -> psycopg2.extensions.connection:
    while True:
        try:
            conn = psycopg2.connect(DATABASE_URL)
            log.info("Connected to PostgreSQL")
            return conn
        except Exception as exc:
            log.error("PostgreSQL unavailable: %s — retrying in 5s", exc)
            time.sleep(5)


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
            log.error("RabbitMQ unavailable: %s — retrying in 5s", exc)
            time.sleep(5)


def make_callback(db: psycopg2.extensions.connection):
    def callback(ch, method, properties, body):
        try:
            data = json.loads(body)
            # Map wire field names to DB column names
            row = {
                "question":   data.get("question"),
                "slug":       data.get("slug"),
                "yes_price":  data.get("yes_price"),
                "no_price":   data.get("no_price"),
                "volume_24h": data.get("volume_24h"),
                "category":   data.get("category"),
                "end_date":   data.get("end_date") or None,
                "fetched_at": data.get("fetched_at"),
            }
            with db.cursor() as cur:
                cur.execute(INSERT_SQL, row)
            db.commit()
            ch.basic_ack(delivery_tag=method.delivery_tag)
            log.info("Stored snapshot: %s", data.get("slug"))
        except Exception as exc:
            log.error("Failed to process message: %s", exc)
            try:
                db.rollback()
            except Exception:
                pass
            # Requeue so we don't lose the message
            ch.basic_nack(delivery_tag=method.delivery_tag, requeue=True)

    return callback


def main() -> None:
    db = connect_postgres()
    init_schema(db)

    while True:
        try:
            mq = connect_rabbitmq()
            channel = mq.channel()
            channel.queue_declare(queue=QUEUE_NAME, durable=True)
            channel.basic_qos(prefetch_count=1)
            channel.basic_consume(
                queue=QUEUE_NAME,
                on_message_callback=make_callback(db),
            )
            log.info("Consuming from %s …", QUEUE_NAME)
            channel.start_consuming()
        except Exception as exc:
            log.error("Consumer loop error: %s — reconnecting", exc)
            time.sleep(5)
            # Reconnect postgres if the connection dropped
            try:
                db.close()
            except Exception:
                pass
            db = connect_postgres()


if __name__ == "__main__":
    main()
