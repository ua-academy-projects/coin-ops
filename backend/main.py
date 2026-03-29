"""
FastAPI Backend — Monero Privacy Analytics API
"""
import sys, os
sys.path.insert(0, os.path.dirname(__file__))

from fastapi import FastAPI, Depends, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, desc, func
from datetime import datetime, timezone
from typing import Optional
import structlog

from database import (
    get_db, Block, NetworkStat, Price,
    PrivacyMetric, NextBlockPrediction as DBPrediction,
    engine, Base
)
from config import get_settings
from api.schemas import (
    StatsResponse, BlockResponse, PrivacyCurrentResponse,
    PrivacyPredictionResponse, PriceResponse, HealthResponse,
    TrendResponse,
)

log = structlog.get_logger()
settings = get_settings()

app = FastAPI(
    title="Monero Privacy Analytics API",
    description="Real-time and predictive privacy metrics for the Monero network",
    version="1.0.0",
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.on_event("startup")
async def startup():
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    log.info("api_started")


@app.get("/health", response_model=HealthResponse)
async def health():
    return HealthResponse(status="ok", timestamp=datetime.now(timezone.utc))


@app.get("/stats", response_model=StatsResponse)
async def get_stats(db: AsyncSession = Depends(get_db)):
    """Combined network stats snapshot"""
    # Latest block
    block_result = await db.execute(
        select(Block).order_by(desc(Block.height)).limit(1)
    )
    latest_block = block_result.scalar_one_or_none()

    # Latest network stat
    ns_result = await db.execute(
        select(NetworkStat).order_by(desc(NetworkStat.timestamp)).limit(1)
    )
    latest_ns = ns_result.scalar_one_or_none()

    # Latest price
    price_result = await db.execute(
        select(Price).order_by(desc(Price.timestamp)).limit(1)
    )
    latest_price = price_result.scalar_one_or_none()

    # Latest privacy
    pm_result = await db.execute(
        select(PrivacyMetric).order_by(desc(PrivacyMetric.created_at)).limit(1)
    )
    latest_pm = pm_result.scalar_one_or_none()

    return StatsResponse(
        block_height=latest_block.height if latest_block else 0,
        block_hash=latest_block.hash if latest_block else "",
        block_timestamp=latest_block.timestamp if latest_block else None,
        tx_count=latest_block.tx_count if latest_block else 0,
        block_size=latest_block.block_size if latest_block else 0,
        difficulty=latest_block.difficulty if latest_block else 0,
        mempool_size=latest_ns.mempool_size if latest_ns else 0,
        avg_tx_per_block=latest_ns.avg_tx_per_block if latest_ns else 0.0,
        avg_fee=latest_ns.avg_fee if latest_ns else 0.0,
        price_usd=latest_price.usd if latest_price else None,
        privacy_score=latest_pm.privacy_score if latest_pm else None,
        risk_level=latest_pm.risk_level if latest_pm else None,
    )


@app.get("/blocks/latest", response_model=list[BlockResponse])
async def get_latest_blocks(limit: int = 20, db: AsyncSession = Depends(get_db)):
    """Get the most recent N blocks"""
    result = await db.execute(
        select(Block).order_by(desc(Block.height)).limit(min(limit, 100))
    )
    blocks = result.scalars().all()
    return [
        BlockResponse(
            height=b.height,
            hash=b.hash,
            timestamp=b.timestamp,
            tx_count=b.tx_count,
            block_size=b.block_size,
            difficulty=b.difficulty,
        )
        for b in blocks
    ]


@app.get("/privacy/current", response_model=PrivacyCurrentResponse)
async def get_privacy_current(db: AsyncSession = Depends(get_db)):
    """Current block privacy score"""
    result = await db.execute(
        select(PrivacyMetric).order_by(desc(PrivacyMetric.created_at)).limit(1)
    )
    pm = result.scalar_one_or_none()
    if not pm:
        raise HTTPException(status_code=404, detail="No privacy data yet")
    return PrivacyCurrentResponse(
        block_height=pm.block_height,
        tx_count=pm.tx_count,
        privacy_score=pm.privacy_score,
        risk_level=pm.risk_level,
        timestamp=pm.created_at,
    )


@app.get("/privacy/history", response_model=list[PrivacyCurrentResponse])
async def get_privacy_history(limit: int = 50, db: AsyncSession = Depends(get_db)):
    """Privacy score history"""
    result = await db.execute(
        select(PrivacyMetric).order_by(desc(PrivacyMetric.created_at)).limit(min(limit, 200))
    )
    metrics = result.scalars().all()
    return [
        PrivacyCurrentResponse(
            block_height=m.block_height,
            tx_count=m.tx_count,
            privacy_score=m.privacy_score,
            risk_level=m.risk_level,
            timestamp=m.created_at,
        )
        for m in metrics
    ]


@app.get("/privacy/prediction", response_model=PrivacyPredictionResponse)
async def get_privacy_prediction(db: AsyncSession = Depends(get_db)):
    """Next block privacy prediction"""
    result = await db.execute(
        select(DBPrediction).order_by(desc(DBPrediction.timestamp)).limit(1)
    )
    pred = result.scalar_one_or_none()
    if not pred:
        raise HTTPException(status_code=404, detail="No prediction data yet")
    return PrivacyPredictionResponse(
        timestamp=pred.timestamp,
        mempool_size=pred.mempool_size,
        expected_tx=pred.expected_tx,
        inclusion_probability=pred.inclusion_probability,
        privacy_score=pred.privacy_score,
        recommendation=pred.recommendation,
    )


@app.get("/price", response_model=PriceResponse)
async def get_price(db: AsyncSession = Depends(get_db)):
    """Latest XMR/USD price"""
    result = await db.execute(
        select(Price).order_by(desc(Price.timestamp)).limit(1)
    )
    price = result.scalar_one_or_none()
    if not price:
        raise HTTPException(status_code=404, detail="No price data yet")
    return PriceResponse(usd=price.usd, timestamp=price.timestamp)


@app.get("/price/history", response_model=list[PriceResponse])
async def get_price_history(limit: int = 100, db: AsyncSession = Depends(get_db)):
    result = await db.execute(
        select(Price).order_by(desc(Price.timestamp)).limit(min(limit, 500))
    )
    prices = result.scalars().all()
    return [PriceResponse(usd=p.usd, timestamp=p.timestamp) for p in prices]


@app.get("/trend", response_model=TrendResponse)
async def get_trend(db: AsyncSession = Depends(get_db)):
    """Transaction trend over last 50 blocks"""
    result = await db.execute(
        select(Block.tx_count, Block.height)
        .order_by(desc(Block.height))
        .limit(50)
    )
    rows = result.all()
    if len(rows) < 5:
        return TrendResponse(slope=None, direction="insufficient_data", block_count=len(rows))

    import numpy as np
    tx_counts = [r[0] for r in reversed(rows)]
    x = np.arange(len(tx_counts), dtype=float)
    y = np.array(tx_counts, dtype=float)
    slope = float(np.polyfit(x, y, 1)[0])
    direction = "increasing" if slope > 0.1 else ("decreasing" if slope < -0.1 else "stable")

    return TrendResponse(slope=round(slope, 4), direction=direction, block_count=len(rows))
