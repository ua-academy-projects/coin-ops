import httpx
import asyncio
from typing import Optional
from tenacity import retry, stop_after_attempt, wait_exponential
import structlog
from config import get_settings

log = structlog.get_logger()
settings = get_settings()


class PriceFetcher:
    def __init__(self):
        self._client: Optional[httpx.AsyncClient] = None
        self._last_prices: dict[str, float] = {}

    async def _get_client(self) -> httpx.AsyncClient:
        if self._client is None or self._client.is_closed:
            self._client = httpx.AsyncClient(timeout=15.0)
        return self._client

    @retry(stop=stop_after_attempt(3), wait=wait_exponential(multiplier=1, min=2, max=10))
    async def fetch_prices_usd(self) -> dict[str, float]:
        client = await self._get_client()
        try:
            url = f"{settings.coingecko_api_url}/simple/price"
            resp = await client.get(url, params={"ids": "monero,bitcoin,ethereum,solana,cardano", "vs_currencies": "usd"})
            resp.raise_for_status()
            data = resp.json()
            
            prices = {}
            for coin, coin_data in data.items():
                if "usd" in coin_data:
                    prices[coin] = float(coin_data["usd"])
                    
            if prices:
                self._last_prices = prices
                log.info("prices_fetched", coins=list(prices.keys()))
            return prices
        except Exception as e:
            log.warning("price_fetch_error", error=str(e))
            return self._last_prices

    async def close(self):
        if self._client and not self._client.is_closed:
            await self._client.aclose()


_price_fetcher: Optional[PriceFetcher] = None


def get_price_fetcher() -> PriceFetcher:
    global _price_fetcher
    if _price_fetcher is None:
        _price_fetcher = PriceFetcher()
    return _price_fetcher
