#!/usr/bin/env pytho

from datetime import datetime, timezone
import json
import logging
import os
import re
import signal
import sys
import time

import pika
import psycopg2
from psycopg2.extras import execute_batch


LOG_FORMAT = "[nbu-rabbit-consumer] %(asctime)s %(levelname)s %(message)s"
LOGGER = logging.getLogger("nbu-rabbit-consumer")

STOP = False


def getenv(name, default=""):
    value = os.getenv(name)
    return value if value else default


def handle_stop(signum, frame):
    global STOP
    STOP = True
    LOGGER.info("received signal %s, shutting down", signum)


def parse_collected_at(value):
    normalized = str(value).replace("Z", "+00:00")
    match = re.match(r"^(.*\.\d{6})\d+([+-]\d\d:\d\d)$", normalized)
    if match:
        normalized = f"{match.group(1)}{match.group(2)}"
    return datetime.fromisoformat(normalized).astimezone(timezone.utc)


def connect_rabbit():
    credentials = pika.PlainCredentials(
        getenv("RABBITMQ_USER", "guest"),
        getenv("RABBITMQ_PASSWORD", "guest"),
    )

    parameters = pika.ConnectionParameters(
        host=getenv("RABBITMQ_HOST", "127.0.0.1"),
        port=int(getenv("RABBITMQ_PORT", "5672")),
        virtual_host=getenv("RABBITMQ_VHOST", "/"),
        credentials=credentials,
        heartbeat=30,
        blocked_connection_timeout=30,
    )

    return pika.BlockingConnection(parameters)


def connect_postgres():
    return psycopg2.connect(
        host=getenv("POSTGRES_HOST", "127.0.0.1"),
        port=int(getenv("POSTGRES_PORT", "5432")),
        dbname=getenv("POSTGRES_DB", "app_db"),
        user=getenv("POSTGRES_USER", "app_user"),
        password=getenv("POSTGRES_PASSWORD", ""),
    )


def normalize_rows(payload):
    if not isinstance(payload, list):
        raise ValueError("payload must be a JSON array")

    rows = []

    for item in payload:
        try:
            exchange_date = datetime.strptime(
                str(item["exchangedate"]),
                "%d.%m.%Y",
            ).date()

            collected_at = parse_collected_at(item["collected_at"])

            rows.append(
                (
                    int(item["r030"]),
                    str(item["txt"]),
                    float(item["rate"]),
                    str(item["cc"]),
                    exchange_date,
                    collected_at,
                )
            )
        except Exception as e:
            LOGGER.warning("skipping bad record: %s | error: %s", item, e)

    return rows


def save_rows(connection, rows):
    if not rows:
        return

    query = """
        INSERT INTO exchange_rates (
            r030,
            txt,
            rate,
            cc,
            exchange_date,
            collected_at
        )
        VALUES (%s, %s, %s, %s, %s, %s)
        ON CONFLICT (cc, exchange_date, collected_at)
        DO UPDATE SET
            r030 = EXCLUDED.r030,
            txt = EXCLUDED.txt,
            rate = EXCLUDED.rate;
    """

    with connection.cursor() as cursor:
        execute_batch(cursor, query, rows, page_size=100)

    connection.commit()


def main():
    global STOP

    logging.basicConfig(level=logging.INFO, format=LOG_FORMAT)

    signal.signal(signal.SIGINT, handle_stop)
    signal.signal(signal.SIGTERM, handle_stop)

    queue = getenv("RABBITMQ_QUEUE", "nbu.exchange.rates")

    while not STOP:
        rabbit_connection = None
        postgres_connection = None

        try:
            postgres_connection = connect_postgres()
            rabbit_connection = connect_rabbit()

            channel = rabbit_connection.channel()
            channel.queue_declare(queue=queue, durable=True)
            channel.basic_qos(prefetch_count=1)

            LOGGER.info("connected to RabbitMQ and PostgreSQL")

            def callback(ch, method, properties, body):
                if STOP:
                    ch.stop_consuming()
                    return

                try:
                    payload = json.loads(body.decode("utf-8"))
                    rows = normalize_rows(payload)

                    save_rows(postgres_connection, rows)

                    ch.basic_ack(delivery_tag=method.delivery_tag)

                    LOGGER.info("stored %s records", len(rows))

                except Exception:
                    postgres_connection.rollback()

                 
                    LOGGER.exception(
                        "failed message: %s",
                        body[:500],
                    )

                    # можно потом заменить на DLQ
                    ch.basic_nack(
                        delivery_tag=method.delivery_tag,
                        requeue=True,
                    )

                    time.sleep(3)

            channel.basic_consume(
                queue=queue,
                on_message_callback=callback,
            )

            channel.start_consuming()

        except Exception:
            LOGGER.exception("connection error, retrying in 5 seconds")
            time.sleep(5)

        finally:
            try:
                if rabbit_connection and rabbit_connection.is_open:
                    rabbit_connection.close()
            except Exception:
                pass

            try:
                if postgres_connection and not postgres_connection.closed:
                    postgres_connection.close()
            except Exception:
                pass

    LOGGER.info("consumer stopped")
    return 0


if __name__ == "__main__":
    sys.exit(main())
