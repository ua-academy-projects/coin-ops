from pydantic import BaseModel
from datetime import datetime
from typing import Optional


class HealthResponse(BaseModel):
    status: str
    timestamp: datetime


class StatsResponse(BaseModel):
    block_height: int
    block_hash: str
    block_timestamp: Optional[datetime]
    tx_count: int
    block_size: int
    difficulty: int
    mempool_size: int
    avg_tx_per_block: float
    avg_fee: float
    price_usd: Optional[float]
    privacy_score: Optional[float]
    risk_level: Optional[str]


class BlockResponse(BaseModel):
    height: int
    hash: str
    timestamp: datetime
    tx_count: int
    block_size: int
    difficulty: int


class PrivacyCurrentResponse(BaseModel):
    block_height: int
    tx_count: int
    privacy_score: float
    risk_level: str
    timestamp: datetime


class PrivacyPredictionResponse(BaseModel):
    timestamp: datetime
    mempool_size: int
    expected_tx: int
    inclusion_probability: float
    privacy_score: float
    recommendation: str


class PriceResponse(BaseModel):
    usd: float
    timestamp: datetime


class TrendResponse(BaseModel):
    slope: Optional[float]
    direction: str
    block_count: int
