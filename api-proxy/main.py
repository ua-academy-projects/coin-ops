import os
import httpx
from fastapi import FastAPI, Query
from fastapi.middleware.cors import CORSMiddleware

NBU_URL = "https://bank.gov.ua/NBUStatService/v1/statdirectory/exchange"

app = FastAPI(title="Coin-Ops API Proxy")

cors_origins = os.getenv("CORS_ORIGINS", "http://localhost:5173").split(",")
app.add_middleware(
    CORSMiddleware,
    allow_origins=cors_origins,
    allow_methods=["GET"],
    allow_headers=["*"],
)


@app.get("/health")
def health():
    return {"status": "ok"}


@app.get("/rates")
async def get_rates(cc: str | None = Query(default=None, description="Currency code filter, e.g. USD")):
    params = {"json": ""}
    if cc:
        params["valcode"] = cc.upper()

    async with httpx.AsyncClient() as client:
        resp = await client.get(NBU_URL, params=params)
        resp.raise_for_status()
        raw = resp.json()

    rates = [
        {
            "code": item["cc"],
            "name": item["txt"],
            "rate": float(item["rate"]),
            "date": item["exchangedate"],
        }
        for item in raw
    ]
    return rates
