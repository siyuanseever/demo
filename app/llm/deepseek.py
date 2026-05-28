import json
import logging
import socket
import time
import urllib.error
import urllib.request

from app.llm.base import LLMResponse, Message


class DeepSeekClient:
    def __init__(
        self,
        api_key: str,
        model: str,
        base_url: str,
        timeout: float = 30,
        thinking: str = "disabled",
        stream: bool = True,
    ) -> None:
        self.api_key = api_key
        self.model = model
        self.base_url = base_url.rstrip("/")
        self.timeout = timeout
        self.thinking = thinking
        self.stream = stream
        self.logger = logging.getLogger(__name__)

    def chat(
        self,
        messages: list[Message],
        *,
        temperature: float = 0.7,
        max_tokens: int = 1200,
        response_format: dict | None = None,
    ) -> LLMResponse:
        payload: dict = {
            "model": self.model,
            "messages": messages,
            "temperature": temperature,
            "max_tokens": max_tokens,
            "stream": self.stream,
        }
        if self.thinking in {"enabled", "disabled"}:
            payload["thinking"] = {"type": self.thinking}
        if response_format:
            payload["response_format"] = response_format

        request = urllib.request.Request(
            f"{self.base_url}/chat/completions",
            data=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
            headers={
                "Authorization": f"Bearer {self.api_key}",
                "Content-Type": "application/json",
            },
            method="POST",
        )

        started_at = time.monotonic()
        self.logger.info(
            "deepseek request start model=%s messages=%s max_tokens=%s stream=%s thinking=%s",
            self.model,
            len(messages),
            max_tokens,
            self.stream,
            self.thinking,
        )
        try:
            with urllib.request.urlopen(request, timeout=self.timeout) as response:
                if self.stream:
                    content, raw = self._read_stream(response)
                else:
                    raw = json.loads(response.read().decode("utf-8"))
                    content = raw["choices"][0]["message"]["content"]
        except urllib.error.HTTPError as error:
            detail = error.read().decode("utf-8", errors="replace")
            self.logger.exception("deepseek http error status=%s", error.code)
            if error.code == 503:
                raise RuntimeError(
                    "DeepSeek 服务当前繁忙（503）。这不是 API key 或本地代码问题，稍后重试或临时切换 Gemini。"
                ) from error
            raise RuntimeError(f"DeepSeek API error {error.code}: {detail}") from error
        except urllib.error.URLError as error:
            self.logger.exception("deepseek network error")
            raise RuntimeError(f"DeepSeek network error: {error.reason}") from error
        except TimeoutError as error:
            self.logger.exception("deepseek timeout")
            raise RuntimeError(f"DeepSeek request timed out after {self.timeout}s") from error
        except socket.timeout as error:
            self.logger.exception("deepseek socket timeout")
            raise RuntimeError(f"DeepSeek request timed out after {self.timeout}s") from error

        model = raw.get("model", self.model)
        elapsed = time.monotonic() - started_at
        self.logger.info(
            "deepseek request done model=%s elapsed=%.2fs chars=%s",
            model,
            elapsed,
            len(content),
        )
        return LLMResponse(content=content, model=model, raw=raw)

    def _read_stream(self, response) -> tuple[str, dict]:
        chunks = []
        last_payload: dict = {"model": self.model}
        for raw_line in response:
            line = raw_line.decode("utf-8", errors="replace").strip()
            if not line or not line.startswith("data:"):
                continue
            data = line.removeprefix("data:").strip()
            if data == "[DONE]":
                return "".join(chunks), last_payload
            payload = json.loads(data)
            last_payload = payload
            choice = payload.get("choices", [{}])[0]
            delta = choice.get("delta", {})
            content = delta.get("content")
            if content:
                chunks.append(content)
            if choice.get("finish_reason"):
                return "".join(chunks), last_payload
        return "".join(chunks), last_payload
