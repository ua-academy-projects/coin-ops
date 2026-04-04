"""RabbitMQ consumer for snapshot events."""

from __future__ import annotations

import json
import logging
import random
import threading
import time
import uuid
from typing import Any, Mapping

import pika

from config import HistoryConfig
from db import pg_conn
from repository import insert_rates

LOG = logging.getLogger("coinops.history.consumer")


def run_consumer_forever(cfg: HistoryConfig, stop_event: threading.Event) -> None:
    """Run RabbitMQ consumer loop with reconnects. Messages are ACKed only after DB commit."""
    reconnect_attempt = 0
    while not stop_event.is_set():
        connection = None
        channel = None
        try:
            params = pika.URLParameters(cfg.rabbitmq_url)
            connection = pika.BlockingConnection(params)
            channel = connection.channel()
            channel.exchange_declare(
                exchange=cfg.rabbitmq_exchange, exchange_type="direct", durable=True,
            )
            channel.queue_declare(queue=cfg.rabbitmq_queue, durable=True)
            channel.queue_bind(
                queue=cfg.rabbitmq_queue,
                exchange=cfg.rabbitmq_exchange,
                routing_key=cfg.rabbitmq_routing_key,
            )
            channel.basic_qos(prefetch_count=cfg.mq_prefetch_count)
            reconnect_attempt = 0
            LOG.info(
                "consumer connected exchange=%s queue=%s key=%s prefetch=%d",
                cfg.rabbitmq_exchange,
                cfg.rabbitmq_queue,
                cfg.rabbitmq_routing_key,
                cfg.mq_prefetch_count,
            )
            while not stop_event.is_set():
                method, _properties, body = channel.basic_get(
                    queue=cfg.rabbitmq_queue, auto_ack=False,
                )
                if method is None:
                    time.sleep(0.2)
                    continue
                try:
                    event_id, rates, malformed = _decode_event(body)
                    if malformed or not rates:
                        if malformed:
                            LOG.warning("ack malformed message, delivery_tag=%s", method.delivery_tag)
                        elif not rates:
                            LOG.debug(
                                "ack message with no rate rows (event_id=%s), delivery_tag=%s",
                                event_id,
                                method.delivery_tag,
                            )
                        channel.basic_ack(method.delivery_tag)
                        continue
                    with pg_conn(cfg) as conn:
                        inserted, attempted = insert_rates(conn, rates, event_id)
                        conn.commit()
                        LOG.info(
                            "persisted %d/%d rows (snapshot_event_id=%s)",
                            inserted,
                            attempted,
                            event_id,
                        )
                    channel.basic_ack(method.delivery_tag)
                except Exception as exc:
                    LOG.exception("consume/insert failed: %s", exc)
                    channel.basic_nack(method.delivery_tag, requeue=True)
        except Exception as exc:
            reconnect_attempt += 1
            exp = min(10, max(0, reconnect_attempt - 1))
            delay = min(cfg.mq_backoff_max, cfg.mq_backoff_initial * (2**exp))
            delay *= 0.5 + random.random()
            LOG.warning(
                "consumer reconnect after error (attempt %d, sleep %.1fs): %s",
                reconnect_attempt,
                delay,
                exc,
            )
            _sleep_interruptible(stop_event, delay)
        finally:
            try:
                if channel and channel.is_open:
                    channel.close()
            except Exception:
                pass
            try:
                if connection and connection.is_open:
                    connection.close()
            except Exception:
                pass


# ---------------------------------------------------------------------------
# Message decoding
# ---------------------------------------------------------------------------


def _decode_event(body: Any) -> tuple[str, list[dict[str, Any]], bool]:
    """
    Return (snapshot_event_id, rates, malformed).

    If malformed the consumer should ACK without requeue to avoid poison-message loops.
    """
    body = _mq_body_to_bytes(body)
    try:
        text = body.decode("utf-8")
    except UnicodeDecodeError:
        LOG.warning("mq payload: invalid utf-8 (%d bytes)", len(body))
        return str(uuid.uuid5(uuid.NAMESPACE_OID, body)), [], True
    try:
        parsed: Any = json.loads(text)
    except json.JSONDecodeError as exc:
        LOG.warning("mq payload: invalid json: %s", exc)
        return str(uuid.uuid5(uuid.NAMESPACE_OID, body)), [], True
    if not isinstance(parsed, dict):
        LOG.warning("mq payload: root is not an object")
        return str(uuid.uuid5(uuid.NAMESPACE_OID, body)), [], True
    payload: Mapping[str, Any] = parsed
    event_id = _stable_event_id(body, payload)
    data = payload.get("data")
    if not isinstance(data, dict):
        return event_id, [], False
    rates_raw = data.get("rates")
    # Go encodes a nil slice as JSON null; treat like [].
    if rates_raw is None:
        rates_list: list[dict[str, Any]] = []
    elif isinstance(rates_raw, list):
        rates_list = [r for r in rates_raw if isinstance(r, dict)]
    else:
        LOG.warning("mq payload: data.rates has unexpected type %s", type(rates_raw).__name__)
        return event_id, [], False
    return event_id, rates_list, False


def _stable_event_id(body: bytes, payload: Mapping[str, Any]) -> str:
    """Prefer proxy event_id; otherwise derive a stable UUID from raw bytes."""
    raw = payload.get("event_id")
    if isinstance(raw, str) and raw.strip():
        try:
            return str(uuid.UUID(raw.strip()))
        except ValueError:
            pass
    return str(uuid.uuid5(uuid.NAMESPACE_OID, body))


def _mq_body_to_bytes(body: Any) -> bytes:
    """pika may deliver bytes, bytearray, or memoryview."""
    if isinstance(body, memoryview):
        return body.tobytes()
    if isinstance(body, bytearray):
        return bytes(body)
    if isinstance(body, bytes):
        return body
    return bytes(body)


def _sleep_interruptible(stop_event: threading.Event, seconds: float) -> None:
    """Sleep up to *seconds* but return early if *stop_event* is set."""
    if seconds <= 0:
        return
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        if stop_event.wait(0.2):
            return
