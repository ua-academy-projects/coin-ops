import importlib.util
import os
import uuid
from pathlib import Path

import psycopg2
import psycopg2.extras
import pytest
from fastapi.testclient import TestClient
from testcontainers.postgres import PostgresContainer


REPO_ROOT = Path(__file__).resolve().parents[3]
HISTORY_SCHEMA_PATH = REPO_ROOT / "history" / "schema.sql"


def load_module(relative_path: str, env: dict[str, str]):
    module_path = REPO_ROOT / relative_path
    previous_values = {key: os.environ.get(key) for key in env}
    try:
        for key, value in env.items():
            os.environ[key] = value

        module_name = f"test_integration_{module_path.stem}_{uuid.uuid4().hex}"
        spec = importlib.util.spec_from_file_location(module_name, module_path)
        module = importlib.util.module_from_spec(spec)
        assert spec.loader is not None
        spec.loader.exec_module(module)
        return module
    finally:
        for key, old_value in previous_values.items():
            if old_value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = old_value


def _normalize_connection_url(url: str) -> str:
    # testcontainers may return SQLAlchemy-style URL with a driver suffix.
    return url.replace("postgresql+psycopg2://", "postgresql://", 1)


@pytest.fixture(scope="session")
def database_url():
    with PostgresContainer("postgres:16-alpine") as postgres:
        yield _normalize_connection_url(postgres.get_connection_url())


@pytest.fixture(scope="session", autouse=True)
def _apply_schema(database_url):
    with open(HISTORY_SCHEMA_PATH, encoding="utf-8") as schema_file:
        ddl = schema_file.read()

    conn = psycopg2.connect(database_url)
    try:
        with conn.cursor() as cur:
            cur.execute(ddl)
        conn.commit()
    finally:
        conn.close()


@pytest.fixture
def db_conn(database_url):
    conn = psycopg2.connect(
        database_url,
        cursor_factory=psycopg2.extras.RealDictCursor,
    )
    try:
        yield conn
    finally:
        conn.close()


@pytest.fixture(autouse=True)
def _clean_tables(database_url):
    yield
    conn = psycopg2.connect(database_url)
    try:
        with conn.cursor() as cur:
            cur.execute(
                """
                TRUNCATE TABLE
                    whale_positions,
                    whales,
                    market_snapshots,
                    price_snapshots
                RESTART IDENTITY CASCADE
                """
            )
        conn.commit()
    finally:
        conn.close()


@pytest.fixture(scope="session")
def history_api_module(database_url):
    return load_module("history/main.py", {"DATABASE_URL": database_url})


@pytest.fixture(scope="session")
def history_consumer_module(database_url):
    return load_module(
        "history/consumer.py",
        {
            "DATABASE_URL": database_url,
            "RABBITMQ_URL": "amqp://guest:guest@localhost:5672/",
        },
    )


@pytest.fixture
def api_client(history_api_module, database_url, monkeypatch):
    def _db_factory():
        return psycopg2.connect(
            database_url,
            cursor_factory=psycopg2.extras.RealDictCursor,
        )

    monkeypatch.setattr(history_api_module, "get_db", _db_factory)
    with TestClient(history_api_module.app) as client:
        yield client
