import importlib.util
import os
import signal
import uuid
from pathlib import Path

import psycopg2
import psycopg2.extras
import pytest
from fastapi.testclient import TestClient
from testcontainers.core import testcontainers_config
from testcontainers.postgres import PostgresContainer


REPO_ROOT = Path(__file__).resolve().parents[3]
BOOTSTRAP_SCRIPT_PATH = REPO_ROOT / "tests" / "python" / "integration" / "postgres_bootstrap.sh"
DEFAULT_TEST_RUNTIME_POSTGRES_IMAGE = (
   "coinops-postgres-runtime:latest"
)
TEST_RUNTIME_POSTGRES_IMAGE = os.environ.get(
    "COINOPS_TEST_POSTGRES_IMAGE",
    DEFAULT_TEST_RUNTIME_POSTGRES_IMAGE,
)
RESTORED_SIGNALS = tuple(
    sig for sig in (signal.SIGINT, getattr(signal, "SIGTERM", None)) if sig is not None
)


def _should_disable_ryuk() -> bool:
    override = os.environ.get("COINOPS_TESTCONTAINERS_DISABLE_RYUK")
    if override is not None:
        return override.lower() in {"1", "true", "yes", "on"}

    # Ryuk currently fails to expose its control port on this Windows Docker setup,
    # which prevents the actual PostgreSQL test container from starting.
    return os.name == "nt"


testcontainers_config.ryuk_disabled = _should_disable_ryuk()


def load_module(relative_path: str, env: dict[str, str]):
    module_path = REPO_ROOT / relative_path
    previous_values = {key: os.environ.get(key) for key in env}
    previous_signal_handlers = {sig: signal.getsignal(sig) for sig in RESTORED_SIGNALS}
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

        for sig, handler in previous_signal_handlers.items():
            signal.signal(sig, handler)


def _normalize_connection_url(url: str) -> str:
    # testcontainers may return SQLAlchemy-style URL with a driver suffix.
    return url.replace("postgresql+psycopg2://", "postgresql://", 1)


@pytest.fixture(scope="session")
def database_url():
    postgres = (
        PostgresContainer(
            TEST_RUNTIME_POSTGRES_IMAGE,
            username="coinops",
            password="test",
            dbname="coinops",
        )
        .with_volume_mapping(REPO_ROOT.as_posix(), "/repo", mode="ro")
        .with_volume_mapping(
            BOOTSTRAP_SCRIPT_PATH.as_posix(),
            "/docker-entrypoint-initdb.d/10-coinops-bootstrap.sh",
            mode="ro",
        )
        .with_command("-c shared_preload_libraries=pg_cron,pgmq -c cron.database_name=coinops")
    )
    with postgres:
        yield _normalize_connection_url(postgres.get_connection_url())


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
            cur.execute("DELETE FROM runtime.dead_letter_audit")
            cur.execute("DELETE FROM runtime.event_retry")
            cur.execute(
                """
                DO $$
                DECLARE
                    table_name text;
                BEGIN
                    FOREACH table_name IN ARRAY ARRAY[
                        'public.q_events',
                        'public.q_events_dlq',
                        'pgmq.q_events',
                        'pgmq.q_events_dlq'
                    ]
                    LOOP
                        IF to_regclass(table_name) IS NOT NULL THEN
                            EXECUTE 'TRUNCATE TABLE ' || table_name || ' RESTART IDENTITY';
                        END IF;
                    END LOOP;
                END
                $$;
                """
            )
        conn.commit()
    finally:
        conn.close()


@pytest.fixture(scope="session")
def history_api_module(database_url):
    return load_module("history/main.py", {"DATABASE_URL": database_url})


@pytest.fixture(scope="session")
def runtime_consumer_module(database_url):
    return load_module("runtime/runtime_consumer.py", {"DATABASE_URL": database_url})


@pytest.fixture
def runtime_db_conn(database_url):
    conn = psycopg2.connect(database_url)
    conn.autocommit = True
    try:
        yield conn
    finally:
        conn.close()


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
