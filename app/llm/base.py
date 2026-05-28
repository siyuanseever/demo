from dataclasses import dataclass
from typing import Protocol


Message = dict[str, str]


@dataclass(frozen=True)
class LLMResponse:
    content: str
    model: str
    raw: dict


class LLMClient(Protocol):
    def chat(
        self,
        messages: list[Message],
        *,
        temperature: float = 0.7,
        max_tokens: int = 1200,
        response_format: dict | None = None,
    ) -> LLMResponse:
        ...

