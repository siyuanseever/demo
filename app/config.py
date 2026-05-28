import os
from dataclasses import dataclass


@dataclass(frozen=True)
class Settings:
    deepseek_api_key: str | None
    deepseek_model: str
    deepseek_base_url: str
    deepseek_timeout: float
    app_db_path: str
    llm_provider: str
    log_path: str
    web_timeout_ms: int


def load_dotenv(path: str = ".env") -> None:
    if not os.path.exists(path):
        return

    with open(path, "r", encoding="utf-8") as file:
        for raw_line in file:
            line = raw_line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            os.environ.setdefault(key.strip(), value.strip().strip('"').strip("'"))


def get_settings() -> Settings:
    load_dotenv()
    return Settings(
        deepseek_api_key=os.getenv("DEEPSEEK_API_KEY"),
        deepseek_model=os.getenv("DEEPSEEK_MODEL", "deepseek-v4-flash"),
        deepseek_base_url=os.getenv("DEEPSEEK_BASE_URL", "https://api.deepseek.com"),
        deepseek_timeout=float(os.getenv("DEEPSEEK_TIMEOUT", "90")),
        app_db_path=os.getenv("APP_DB_PATH", "data/app.db"),
        llm_provider=os.getenv("LLM_PROVIDER", "deepseek"),
        log_path=os.getenv("APP_LOG_PATH", "logs/app.log"),
        web_timeout_ms=int(os.getenv("WEB_TIMEOUT_MS", "20000")),
    )
