import httpx
import asyncio
from typing import Any, Optional
from tenacity import retry, stop_after_attempt, wait_exponential
import structlog
from config import get_settings

log = structlog.get_logger()
settings = get_settings()


class MoneroRPCError(Exception):
    pass


class MoneroRPCClient:
    def __init__(self):
        self.url = settings.monero_rpc_url
        self._client: Optional[httpx.AsyncClient] = None

    async def _get_client(self) -> httpx.AsyncClient:
        if self._client is None or self._client.is_closed:
            self._client = httpx.AsyncClient(timeout=30.0)
        return self._client

    @retry(stop=stop_after_attempt(3), wait=wait_exponential(multiplier=1, min=1, max=5))
    async def _call(self, method: str, params: dict = None) -> Any:
        client = await self._get_client()
        payload = {
            "jsonrpc": "2.0",
            "id": "0",
            "method": method,
        }
        if params:
            payload["params"] = params

        try:
            resp = await client.post(self.url, json=payload)
            resp.raise_for_status()
            data = resp.json()
            if "error" in data:
                raise MoneroRPCError(f"RPC error: {data['error']}")
            return data.get("result", {})
        except httpx.HTTPError as e:
            log.error("monero_rpc_http_error", method=method, error=str(e))
            raise

    async def get_block_count(self) -> int:
        result = await self._call("get_block_count")
        return result.get("count", 0)

    async def get_block(self, height: int) -> dict:
        result = await self._call("get_block", {"height": height})
        return result

    async def get_last_block_header(self) -> dict:
        result = await self._call("get_last_block_header")
        return result.get("block_header", {})

    async def get_block_header_by_height(self, height: int) -> dict:
        result = await self._call("get_block_header_by_height", {"height": height})
        return result.get("block_header", {})

    async def get_transaction_pool(self) -> dict:
        """Call the non-JSON-RPC endpoint for tx pool"""
        client = await self._get_client()
        base = settings.monero_rpc_url.replace("/json_rpc", "")
        try:
            resp = await client.post(f"{base}/get_transaction_pool")
            resp.raise_for_status()
            return resp.json()
        except Exception as e:
            log.warning("tx_pool_fetch_error", error=str(e))
            return {"transactions": [], "spent_key_images": []}

    async def get_info(self) -> dict:
        result = await self._call("get_info")
        return result

    async def close(self):
        if self._client and not self._client.is_closed:
            await self._client.aclose()


# Singleton
_rpc_client: Optional[MoneroRPCClient] = None


def get_rpc_client() -> MoneroRPCClient:
    global _rpc_client
    if _rpc_client is None:
        _rpc_client = MoneroRPCClient()
    return _rpc_client
