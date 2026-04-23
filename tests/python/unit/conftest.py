import importlib.util
import os
import uuid
from pathlib import Path

import pytest


REPO_ROOT = Path(__file__).resolve().parents[3]


def load_module(relative_path: str, env: dict[str, str]):
    module_path = REPO_ROOT / relative_path
    previous_values = {key: os.environ.get(key) for key in env}

    try:
        for key, value in env.items():
            os.environ[key] = value

        module_name = f"test_{module_path.stem}_{uuid.uuid4().hex}"
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


def description_from_names(*names: str):
    return [(name, None, None, None, None, None, None) for name in names]


class CursorSpy:
    def __init__(self, rows=None, description=None):
        self.rows = rows or []
        self.description = description or []
        self.executed = []

    def execute(self, sql, params=None):
        self.executed.append((sql, params))

    def fetchall(self):
        return list(self.rows)

    def fetchone(self):
        if not self.rows:
            return None
        return self.rows[0]

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc, tb):
        return False


class ConnectionSpy:
    def __init__(self, rows=None, description=None):
        self.cursor_obj = CursorSpy(rows=rows, description=description)
        self.closed = False
        self.rollback_calls = 0
        self.commit_calls = 0

    def cursor(self):
        return self.cursor_obj

    def close(self):
        self.closed = True

    def rollback(self):
        self.rollback_calls += 1

    def commit(self):
        self.commit_calls += 1


class ChannelSpy:
    def __init__(self):
        self.acks = []
        self.nacks = []
        self.published = []

    def basic_ack(self, delivery_tag):
        self.acks.append(delivery_tag)

    def basic_nack(self, delivery_tag, requeue):
        self.nacks.append((delivery_tag, requeue))

    def basic_publish(self, *args, **kwargs):
        self.published.append((args, kwargs))


@pytest.fixture
def history_main_module():
    return load_module(
        "history/main.py",
        {"DATABASE_URL": "postgresql://coinops:test@localhost:5432/coinops"},
    )


@pytest.fixture
def history_consumer_module():
    return load_module(
        "history/consumer.py",
        {
            "DATABASE_URL": "postgresql://coinops:test@localhost:5432/coinops",
            "RABBITMQ_URL": "amqp://guest:guest@localhost:5672/",
        },
    )


@pytest.fixture
def runtime_consumer_module():
    return load_module(
        "runtime/runtime_consumer.py",
        {"DATABASE_URL": "postgresql://coinops:test@localhost:5432/coinops"},
    )
