import os
from dataclasses import dataclass


@dataclass(frozen=True)
class Settings:
    deepseek_api_key: str | None
    deepseek_model: str
    deepseek_base_url: str
    deepseek_timeout: float
    deepseek_thinking: str
    deepseek_reasoning_effort: str
    deepseek_stream: bool
    app_db_path: str
    llm_provider: str
    log_path: str
    web_timeout_ms: int
    web_host: str
    web_port: int
    sync_token: str | None
    intent_confidence_threshold: float
    intent_quick_max_tokens: int
    intent_timeout_ms: int
    prompt_tracking_enabled: bool


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
        deepseek_thinking=os.getenv("DEEPSEEK_THINKING", "disabled"),
        deepseek_reasoning_effort=os.getenv("DEEPSEEK_REASONING_EFFORT", "high"),
        deepseek_stream=os.getenv("DEEPSEEK_STREAM", "true").lower() == "true",
        app_db_path=os.getenv("APP_DB_PATH", "data/app.db"),
        llm_provider=os.getenv("LLM_PROVIDER", "deepseek"),
        log_path=os.getenv("APP_LOG_PATH", "logs/app.log"),
        web_timeout_ms=int(os.getenv("WEB_TIMEOUT_MS", "20000")),
        web_host=os.getenv("WEB_HOST", "127.0.0.1"),
        web_port=int(os.getenv("WEB_PORT", "8765")),
        sync_token=os.getenv("SENSEN_SYNC_TOKEN"),
        intent_confidence_threshold=float(os.getenv("INTENT_CONFIDENCE_THRESHOLD", "0.85")),
        intent_quick_max_tokens=int(os.getenv("INTENT_QUICK_MAX_TOKENS", "400")),
        intent_timeout_ms=int(os.getenv("INTENT_TIMEOUT_MS", "8000")),
        prompt_tracking_enabled=os.getenv("PROMPT_TRACKING_ENABLED", "false").lower() == "true",
    )
