import json
import time

from app.config import get_settings
from app.llm.deepseek import DeepSeekClient
from app.logging_setup import setup_logging


def main() -> None:
    settings = get_settings()
    setup_logging(settings.log_path)
    if not settings.deepseek_api_key:
        raise SystemExit("缺少 DEEPSEEK_API_KEY。")

    client = DeepSeekClient(
        api_key=settings.deepseek_api_key,
        model=settings.deepseek_model,
        base_url=settings.deepseek_base_url,
        timeout=settings.deepseek_timeout,
    )
    started_at = time.monotonic()
    print("DeepSeek ping")
    print(f"base_url={settings.deepseek_base_url}")
    print(f"model={settings.deepseek_model}")
    print(f"timeout={settings.deepseek_timeout}s")
    print(f"has_key={bool(settings.deepseek_api_key)}")

    response = client.chat(
        [
            {"role": "system", "content": "You are a concise assistant."},
            {"role": "user", "content": "Reply with exactly: pong"},
        ],
        temperature=0,
        max_tokens=16,
    )
    print(f"elapsed={time.monotonic() - started_at:.2f}s")
    print(f"model={response.model}")
    print("content=", response.content)
    print("raw_keys=", sorted(response.raw.keys()))
    print("usage=", json.dumps(response.raw.get("usage", {}), ensure_ascii=False))


if __name__ == "__main__":
    main()

