import importlib.util
import os
import signal
import uuid
from pathlib import Path

import pytest


REPO_ROOT = Path(__file__).resolve().parents[3]
RESTORED_SIGNALS = tuple(
    sig for sig in (signal.SIGINT, getattr(signal, "SIGTERM", None)) if sig is not None
)


def load_module(relative_path: str, env: dict[str, str]):
    module_path = REPO_ROOT / relative_path
    previous_values = {key: os.environ.get(key) for key in env}
    previous_signal_handlers = {sig: signal.getsignal(sig) for sig in RESTORED_SIGNALS}

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

        for sig, handler in previous_signal_handlers.items():
            signal.signal(sig, handler)

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
