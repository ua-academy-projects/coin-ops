"""
Privacy Engine — computes current and predictive privacy metrics.

Core idea: Monero's privacy never "breaks"; this estimates the
*quality of anonymity* in a given block context.
"""
from dataclasses import dataclass
from typing import Optional
import numpy as np
import structlog

log = structlog.get_logger()

IDEAL_TX_MIN = 20
IDEAL_TX_MAX = 30
IDEAL_TX_COUNT = (IDEAL_TX_MIN + IDEAL_TX_MAX) / 2  # 25


@dataclass
class CurrentPrivacy:
    block_height: int
    tx_count: int
    privacy_score: float
    risk_level: str
    recommendation: str


@dataclass
class PredictionInput:
    mempool_tx_count: int
    avg_tx_last_n_blocks: float
    avg_tx_size_bytes: int
    median_block_size_bytes: int
    your_fee: float
    avg_fee_in_mempool: float


@dataclass
class NextBlockPrediction:
    mempool_size: int
    expected_tx: int
    inclusion_probability: float
    privacy_score: float
    risk_level: str
    recommendation: str
    blocks_to_wait: Optional[int]
    tx_trend: Optional[float]


def compute_current_privacy(block_height: int, tx_count: int) -> CurrentPrivacy:
    """
    Simple formula: privacy_score = min(1, tx_count / 20)
    More transactions → harder to trace → higher anonymity quality.
    """
    privacy_score = min(1.0, tx_count / IDEAL_TX_MIN)
    risk_level, recommendation = classify_risk(privacy_score)

    log.debug("current_privacy_computed",
              height=block_height, tx_count=tx_count, score=privacy_score)

    return CurrentPrivacy(
        block_height=block_height,
        tx_count=tx_count,
        privacy_score=round(privacy_score, 4),
        risk_level=risk_level,
        recommendation=recommendation,
    )


def compute_next_block_prediction(inp: PredictionInput) -> NextBlockPrediction:
    """
    Multi-step prediction of anonymity quality in the next block.
    """
    # Step 2: Estimate capacity
    avg_tx_size = inp.avg_tx_size_bytes if inp.avg_tx_size_bytes > 0 else 2000
    median_block = inp.median_block_size_bytes if inp.median_block_size_bytes > 0 else 300_000

    max_tx = max(1, median_block // avg_tx_size)

    # Step 3: Predict tx count
    expected_tx = min(inp.mempool_tx_count, max_tx)

    # Step 4: Inclusion probability
    your_fee = inp.your_fee if inp.your_fee > 0 else inp.avg_fee_in_mempool
    avg_fee = inp.avg_fee_in_mempool if inp.avg_fee_in_mempool > 0 else 1e-6
    inclusion_probability = min(1.0, your_fee / avg_fee)

    # Step 5: Privacy score
    privacy_score = (expected_tx / IDEAL_TX_COUNT) * inclusion_probability
    privacy_score = min(1.0, privacy_score)

    # Step 6: Risk classification
    risk_level, recommendation = classify_risk(privacy_score)

    # Advanced: blocks to wait estimate
    blocks_to_wait = None
    if risk_level == "LOW" and inp.avg_tx_last_n_blocks > 0:
        needed = IDEAL_TX_MIN - inp.mempool_tx_count
        if needed > 0:
            blocks_to_wait = max(1, int(needed / inp.avg_tx_last_n_blocks))

    return NextBlockPrediction(
        mempool_size=inp.mempool_tx_count,
        expected_tx=expected_tx,
        inclusion_probability=round(inclusion_probability, 4),
        privacy_score=round(privacy_score, 4),
        risk_level=risk_level,
        recommendation=recommendation,
        blocks_to_wait=blocks_to_wait,
        tx_trend=None,  # computed separately via trend analysis
    )


def compute_tx_trend(tx_counts: list[int]) -> Optional[float]:
    """
    Linear regression slope over recent block tx counts.
    Positive = growing, negative = declining.
    """
    if len(tx_counts) < 5:
        return None
    x = np.arange(len(tx_counts), dtype=float)
    y = np.array(tx_counts, dtype=float)
    slope = float(np.polyfit(x, y, 1)[0])
    return round(slope, 4)


def classify_risk(score: float) -> tuple[str, str]:
    if score < 0.3:
        return "LOW", "WAIT — anonymity set too small, defer transaction"
    elif score < 0.7:
        return "MEDIUM", "OPTIONAL WAIT — moderate privacy, consider waiting for busier block"
    else:
        return "HIGH", "SEND — strong anonymity set, good time to transact"


def detect_peak_period(timestamps_and_counts: list[tuple]) -> bool:
    """
    Simple heuristic: if the last 5 snapshots average is 1.5x the 24h average,
    we're in a peak period.
    """
    if len(timestamps_and_counts) < 10:
        return False
    counts = [c for _, c in timestamps_and_counts]
    recent_avg = np.mean(counts[-5:])
    overall_avg = np.mean(counts)
    return bool(recent_avg > 1.5 * overall_avg)
