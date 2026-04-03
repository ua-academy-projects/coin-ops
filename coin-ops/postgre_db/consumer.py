"""
db_process/consumer.py

Consumes rate messages from RabbitMQ (fanout exchange "rates")
and persists them into PostgreSQL currency_rates table.
"""

import json
import logging
import os
import time

import psycopg
import pika

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [db_process] %(levelname)s %(message)s",
)
log = logging.getLogger(__name__)

RABBITMQ_URL = os.getenv("RABBITMQ_URL", "amqp://coinops:coinops123@localhost:5672/")
DATABASE_URL = os.getenv(
    "DATABASE_URL", "postgresql://coinops:coinops123@localhost:5432/coinops"
)

INSERT_SQL = """
    INSERT INTO currency_rates
        (currency_code, currency_name, source, rate, base_currency, fetched_at)
    VALUES
        (%s, %s, %s, %s, %s, %s)
"""


def callback(ch, method, _props, body):
    try:
        msg = json.loads(body)
        with psycopg.connect(DATABASE_URL) as conn, conn.cursor() as cur:
            cur.execute(INSERT_SQL, (
                msg["currency_code"], msg["currency_name"], msg["source"],
                msg["rate"], msg["base_currency"], msg["fetched_at"],
            ))
        log.info(
            "Saved  [%s] %s/%s = %s",
            msg["source"], msg["currency_code"], msg["base_currency"], msg["rate"],
        )
        ch.basic_ack(delivery_tag=method.delivery_tag)
    except Exception as exc:
        log.error("Failed to process message: %s — %s", exc, body[:200])
        ch.basic_nack(delivery_tag=method.delivery_tag, requeue=False)


def run():
    params = pika.URLParameters(RABBITMQ_URL)
    conn = pika.BlockingConnection(params)
    ch = conn.channel()

    ch.exchange_declare("rates", exchange_type="fanout", durable=True)
    result = ch.queue_declare("rates_queue", durable=True)
    ch.queue_bind(result.method.queue, "rates")
    ch.basic_qos(prefetch_count=20)
    ch.basic_consume(result.method.queue, callback)

    log.info("Waiting for messages on exchange 'rates'…")
    ch.start_consuming()


def main():
    while True:
        try:
            run()
        except Exception as exc:
            log.error("Connection lost: %s — reconnecting in 5 s", exc)
            time.sleep(5)


if __name__ == "__main__":
    main()
