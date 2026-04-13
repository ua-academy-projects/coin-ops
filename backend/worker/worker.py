"""
Worker — runs every N seconds, collects Monero data, computes metrics,
stores results in PostgreSQL.
"""
import asyncio
import sys
import os
import json
import aio_pika
sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

from datetime import datetime, timezone
import time
import structlog
from sqlalchemy import select, func, text
from database import AsyncSessionLocal, Block, NetworkStat, Price, PrivacyMetric, NextBlockPrediction as DBPrediction
from core.monero_rpc import get_rpc_client, MoneroRPCError
from core.privacy_engine import (
    compute_current_privacy,
    compute_next_block_prediction,
    compute_tx_trend,
    PredictionInput,
)
from core.price_fetcher import get_price_fetcher
from config import get_settings

log = structlog.get_logger()
settings = get_settings()

# Price update throttle — CoinGecko free tier: ~30 req/min
PRICE_UPDATE_EVERY_N_CYCLES = 30  # ~every 5 minutes at 10s interval


class Worker:
    def __init__(self):
        self.rpc = get_rpc_client()
        self.price_fetcher = get_price_fetcher()
        self._cycle = 0
        self._last_height = -1
        self._last_price_fetch_time = 0.0
        self._rabbitmq_conn = None
        self._rabbitmq_channel = None

    async def _setup_rabbitmq(self):
        if not self._rabbitmq_conn or self._rabbitmq_conn.is_closed:
            try:
                self._rabbitmq_conn = await aio_pika.connect_robust(settings.rabbitmq_url)
                self._rabbitmq_channel = await self._rabbitmq_conn.channel()
                log.info("worker_rabbitmq_connected")
            except Exception as e:
                log.error("worker_rabbitmq_connection_failed", error=str(e))

    async def run(self):
        log.info("worker_starting", interval=settings.worker_interval_seconds)
        await self._setup_rabbitmq()
        while True:
            try:
                await self._cycle_once()
            except Exception as e:
                log.error("worker_cycle_error", error=str(e), exc_info=True)
            self._cycle += 1
            await asyncio.sleep(settings.worker_interval_seconds)

    async def _cycle_once(self):
        async with AsyncSessionLocal() as session:
            # 1. Get latest block height
            try:
                height = await self.rpc.get_block_count()
                height -= 1  # current best block
            except Exception as e:
                log.error("rpc_block_count_failed", error=str(e))
                return

            # 2. Fetch & store new blocks
            if height > self._last_height:
                await self._ingest_block(session, height)
                self._last_height = height

            # 3. Fetch mempool
            mempool_data = await self._get_mempool_data()

            # 4. Compute avg stats from last N blocks
            avg_data = await self._compute_averages(session)

            # 5. Store network stats
            ns = NetworkStat(
                mempool_size=mempool_data["tx_count"],
                avg_tx_per_block=avg_data["avg_tx"],
                avg_fee=mempool_data["avg_fee"],
            )
            session.add(ns)

            # 6. Compute current privacy
            privacy = compute_current_privacy(height, avg_data["latest_tx_count"])
            pm = PrivacyMetric(
                block_height=height,
                tx_count=avg_data["latest_tx_count"],
                privacy_score=privacy.privacy_score,
                risk_level=privacy.risk_level,
            )
            session.add(pm)

            # 7. Compute next block prediction
            pred_input = PredictionInput(
                mempool_tx_count=mempool_data["tx_count"],
                avg_tx_last_n_blocks=avg_data["avg_tx"],
                avg_tx_size_bytes=mempool_data["avg_tx_size"],
                median_block_size_bytes=avg_data["median_block_size"],
                your_fee=mempool_data["avg_fee"],
                avg_fee_in_mempool=mempool_data["avg_fee"],
            )
            pred = compute_next_block_prediction(pred_input)
            db_pred = DBPrediction(
                mempool_size=pred.mempool_size,
                expected_tx=pred.expected_tx,
                inclusion_probability=pred.inclusion_probability,
                privacy_score=pred.privacy_score,
                recommendation=pred.recommendation,
            )
            session.add(db_pred)

            # 8. Fetch prices (throttled by time)
            now = time.time()
            if now - self._last_price_fetch_time >= 300:  # 5 minutes
                prices = await self.price_fetcher.fetch_prices_usd()
                if prices:
                    for coin_str, usd_val in prices.items():
                        session.add(Price(usd=usd_val, coin_id=coin_str))
                self._last_price_fetch_time = now

            await session.commit()
            
            if self._rabbitmq_channel and not self._rabbitmq_channel.is_closed:
                try:
                    exchange = self._rabbitmq_channel.default_exchange
                    msg = {
                        "event": "metrics_computed",
                        "block_height": height,
                        "privacy_score": privacy.privacy_score,
                        "risk_level": privacy.risk_level,
                        "timestamp": datetime.now(timezone.utc).isoformat()
                    }
                    await exchange.publish(
                        aio_pika.Message(body=json.dumps(msg).encode()),
                        routing_key="monero_events"
                    )
                except Exception as e:
                    log.error("worker_publish_error", error=str(e))

            log.info("worker_cycle_complete",
                     height=height,
                     mempool=mempool_data["tx_count"],
                     privacy_score=privacy.privacy_score,
                     risk=privacy.risk_level)

    async def _ingest_block(self, session, height: int):
        # Check if already stored
        existing = await session.get(Block, height)
        if existing:
            return

        try:
            header = await self.rpc.get_block_header_by_height(height)
            block = Block(
                height=height,
                hash=header.get("hash", ""),
                timestamp=datetime.fromtimestamp(header.get("timestamp", 0), tz=timezone.utc).replace(tzinfo=None),
                tx_count=header.get("num_txes", 0),
                block_size=header.get("block_size", 0),
                difficulty=header.get("difficulty", 0),
            )
            session.add(block)
            log.debug("block_ingested", height=height, tx_count=block.tx_count)
        except Exception as e:
            log.error("block_ingest_error", height=height, error=str(e))

    async def _get_mempool_data(self) -> dict:
        try:
            pool = await self.rpc.get_transaction_pool()
            txs = pool.get("transactions", [])
            tx_count = len(txs)
            fees = [tx.get("fee", 0) for tx in txs if tx.get("fee")]
            avg_fee = sum(fees) / len(fees) if fees else 0.0
            sizes = [tx.get("blob_size", 2000) for tx in txs if tx.get("blob_size")]
            avg_size = int(sum(sizes) / len(sizes)) if sizes else 2000
            return {
                "tx_count": tx_count,
                "avg_fee": avg_fee,
                "avg_tx_size": avg_size,
            }
        except Exception as e:
            log.warning("mempool_fetch_error", error=str(e))
            return {"tx_count": 0, "avg_fee": 0.0, "avg_tx_size": 2000}

    async def _compute_averages(self, session) -> dict:
        n = settings.blocks_history_for_avg
        result = await session.execute(
            select(Block.tx_count, Block.block_size)
            .order_by(Block.height.desc())
            .limit(n)
        )
        rows = result.all()
        if not rows:
            return {"avg_tx": 10.0, "median_block_size": 300_000, "latest_tx_count": 0}

        tx_counts = [r[0] for r in rows]
        block_sizes = [r[1] for r in rows]
        avg_tx = sum(tx_counts) / len(tx_counts)
        sorted_sizes = sorted(block_sizes)
        median_size = sorted_sizes[len(sorted_sizes) // 2]
        latest_tx = tx_counts[0] if tx_counts else 0

        return {
            "avg_tx": round(avg_tx, 2),
            "median_block_size": median_size,
            "latest_tx_count": latest_tx,
        }


async def main():
    import structlog
    structlog.configure(
        processors=[
            structlog.stdlib.add_log_level,
            structlog.dev.ConsoleRenderer(),
        ]
    )
    worker = Worker()
    await worker.run()


if __name__ == "__main__":
    asyncio.run(main())
