from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession, async_sessionmaker
from sqlalchemy.orm import DeclarativeBase, mapped_column, Mapped
from sqlalchemy import Integer, Text, Float, BigInteger, TIMESTAMP, func
from datetime import datetime
from typing import Optional
from config import get_settings

settings = get_settings()

engine = create_async_engine(settings.database_url, echo=False, pool_size=10, max_overflow=20)
AsyncSessionLocal = async_sessionmaker(engine, expire_on_commit=False)


class Base(DeclarativeBase):
    pass


class Block(Base):
    __tablename__ = "blocks"
    height: Mapped[int] = mapped_column(Integer, primary_key=True)
    hash: Mapped[str] = mapped_column(Text, nullable=False)
    timestamp: Mapped[datetime] = mapped_column(TIMESTAMP, nullable=False)
    tx_count: Mapped[int] = mapped_column(Integer, nullable=False)
    block_size: Mapped[int] = mapped_column(Integer, nullable=False)
    difficulty: Mapped[int] = mapped_column(BigInteger, nullable=False)
    created_at: Mapped[datetime] = mapped_column(TIMESTAMP, server_default=func.now())


class NetworkStat(Base):
    __tablename__ = "network_stats"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    timestamp: Mapped[datetime] = mapped_column(TIMESTAMP, server_default=func.now())
    mempool_size: Mapped[int] = mapped_column(Integer, nullable=False)
    avg_tx_per_block: Mapped[float] = mapped_column(Float, nullable=False)
    avg_fee: Mapped[float] = mapped_column(Float, nullable=False, default=0)


class Price(Base):
    __tablename__ = "price"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    timestamp: Mapped[datetime] = mapped_column(TIMESTAMP, server_default=func.now())
    usd: Mapped[float] = mapped_column(Float, nullable=False)


class PrivacyMetric(Base):
    __tablename__ = "privacy_metrics"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    block_height: Mapped[int] = mapped_column(Integer, nullable=False)
    tx_count: Mapped[int] = mapped_column(Integer, nullable=False)
    privacy_score: Mapped[float] = mapped_column(Float, nullable=False)
    risk_level: Mapped[str] = mapped_column(Text, nullable=False)
    created_at: Mapped[datetime] = mapped_column(TIMESTAMP, server_default=func.now())


class NextBlockPrediction(Base):
    __tablename__ = "next_block_prediction"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    timestamp: Mapped[datetime] = mapped_column(TIMESTAMP, server_default=func.now())
    mempool_size: Mapped[int] = mapped_column(Integer, nullable=False)
    expected_tx: Mapped[int] = mapped_column(Integer, nullable=False)
    inclusion_probability: Mapped[float] = mapped_column(Float, nullable=False)
    privacy_score: Mapped[float] = mapped_column(Float, nullable=False)
    recommendation: Mapped[str] = mapped_column(Text, nullable=False)


async def get_db() -> AsyncSession:
    async with AsyncSessionLocal() as session:
        yield session
