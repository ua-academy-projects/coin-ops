from pydantic_settings import BaseSettings
from functools import lru_cache
import os


class Settings(BaseSettings):
    # Database
    database_url: str = "postgresql+asyncpg://monero:monero@localhost:5432/monero_privacy"
    database_url_sync: str = "postgresql://monero:monero@localhost:5432/monero_privacy"

    # Monero RPC
    monero_rpc_host: str = "127.0.0.1"
    monero_rpc_port: int = 18081
    monero_rpc_url: str = ""

    # CoinGecko
    coingecko_api_url: str = "https://api.coingecko.com/api/v3"

    # Worker
    worker_interval_seconds: int = 10
    blocks_history_for_avg: int = 50

    # Privacy
    ideal_tx_count_min: int = 20
    ideal_tx_count_max: int = 30

    # Redis & RabbitMQ
    redis_url: str = "redis://localhost:6379/0"
    rabbitmq_url: str = "amqp://guest:guest@localhost:5672/"
    session_secret_key: str = "super-secret-session-key-change-in-prod"

    # CORS
    cors_origins: list[str] = ["*"]

    class Config:
        env_file = ".env"
        env_file_encoding = "utf-8"

    def model_post_init(self, __context):
        if not self.monero_rpc_url:
            object.__setattr__(
                self,
                "monero_rpc_url",
                f"http://{self.monero_rpc_host}:{self.monero_rpc_port}/json_rpc"
            )


@lru_cache()
def get_settings() -> Settings:
    return Settings()
