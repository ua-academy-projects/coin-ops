import os
from fastapi import FastAPI, Query
from fastapi.middleware.cors import CORSMiddleware
import psycopg
from psycopg.rows import dict_row

DATABASE_URL = os.getenv(
    "DATABASE_URL",
    "postgresql://coinops:coinops123@localhost:5432/coinops"
)

app = FastAPI(title="CoinOps API")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["GET"],
    allow_headers=["*"],
)


def get_db():
    return psycopg.connect(DATABASE_URL, row_factory=dict_row)


@app.get("/api/currencies")
def list_currencies():
    with get_db() as conn, conn.cursor() as cur:
        cur.execute("""
            SELECT DISTINCT currency_code, currency_name, source, base_currency
            FROM currency_rates
            ORDER BY source, currency_code, base_currency
        """)
        return cur.fetchall()


@app.get("/api/rates/latest")
def latest_rates():
    with get_db() as conn, conn.cursor() as cur:
        cur.execute("""
            SELECT DISTINCT ON (currency_code, base_currency, source)
                currency_code,
                currency_name,
                source,
                rate,
                base_currency,
                fetched_at
            FROM currency_rates
            ORDER BY currency_code, base_currency, source, fetched_at DESC
        """)
        return cur.fetchall()


@app.get("/api/rates/history/{currency_code}")
def history(
    currency_code: str,
    base: str = Query(default="USD"),
    limit: int = Query(default=200, le=500),
):
    with get_db() as conn, conn.cursor() as cur:
        cur.execute("""
            SELECT rate, fetched_at
            FROM currency_rates
            WHERE currency_code = %s AND base_currency = %s
            ORDER BY fetched_at DESC
            LIMIT %s
        """, (currency_code.upper(), base.upper(), limit))
        rows = cur.fetchall()
    return list(reversed(rows))
