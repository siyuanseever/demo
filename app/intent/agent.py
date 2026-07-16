import json
import logging
import time
from pathlib import Path
from typing import cast

from app.intent.schema import IntentResult, IntentType, InteractionType, RiskLevel
from app.llm.base import LLMClient

PROMPT_DIR = Path(__file__).resolve().parents[1] / "prompts"

VALID_INTENTS = {"QUICK_REPLY", "DEEP_REPLY", "CLARIFY", "INTERACTION"}
VALID_MODES = {"stabilize", "validate", "insight", "action", "mixed"}
VALID_INTERACTIONS = {"breathing", "body_scan", "mood_check", "mini_game"}


class IntentAgent:
    """
    统一意图识别 Agent。

    职责：
    1. 使用轻量模型（deepseek-v4-flash no-thinking）快速分析用户输入
    2. 一次判断完成：意图分类、情绪评估、心理状态、角色选取、回复模式、检索词生成
    3. CLARIFY 时直接生成追问回复（避免二次 LLM 调用）
    4. INTERACTION 时识别交互类型
    5. 提供 confidence 供上层路由决策

    与现有系统的关系：
    - 替代原有的 _choose_reply_roles (thinking 模式) 作为快速前置层
    - 当 confidence 高时，IntentAgent 的输出可直接作为 route_plan 使用
    - 当 confidence 低时，回退到原有的 thinking 模式策略规划
    """

    def __init__(
        self,
        llm: LLMClient,
        confidence_threshold: float = 0.85,
        max_history_turns: int = 5,
        max_tokens: int = 500,
    ) -> None:
        self.llm = llm
        self.confidence_threshold = confidence_threshold
        self.max_history_turns = max_history_turns
        self.max_tokens = max_tokens
        self.logger = logging.getLogger(__name__)
        self._prompt = (PROMPT_DIR / "intent_recognition.md").read_text(encoding="utf-8")

    def recognize(
        self,
        user_text: str,
        conversation_history: list[dict] | None = None,
    ) -> IntentResult:
        """
        对用户输入进行意图识别。

        Args:
            user_text: 用户本轮输入
            conversation_history: 最近 N 轮对话，每轮是 {"role": "user"|"assistant", "content": str}

        Returns:
            IntentResult: 包含意图、置信度、情绪、风险等级、角色选择、追问回复等
        """
        started_at = time.monotonic()
        history_text = self._render_history(conversation_history or [])

        messages = [
            {"role": "system", "content": self._prompt},
            {
                "role": "user",
                "content": f"最近对话：\n{history_text}\n\n用户本轮输入：\n{user_text}",
            },
        ]

        response = None
        try:
            if hasattr(self.llm, "set_context"):
                self.llm.set_context(call_type="intent_recognition")  # type: ignore[attr-defined]
            response = self.llm.chat(
                messages,
                temperature=0.1,
                max_tokens=self.max_tokens,
                response_format={"type": "json_object"},
                thinking="disabled",
            )
            raw = json.loads(response.content)
            result = self._normalize(raw)
        except (json.JSONDecodeError, KeyError, TypeError) as error:
            self.logger.warning("intent parse failed error=%s raw=%s", error, getattr(response, "content", "")[:200])
            result = self._fallback_result(user_text)
        except Exception:
            self.logger.exception("intent recognition failed")
            result = self._fallback_result(user_text)

        elapsed = time.monotonic() - started_at
        self.logger.info(
            "intent done intent=%s confidence=%.2f risk=%s emotion=%s mode=%s elapsed=%.2fs",
            result.intent,
            result.confidence,
            result.risk_level,
            result.emotion,
            result.response_mode,
            elapsed,
        )
        return result

    def _render_history(self, history: list[dict]) -> str:
        if not history:
            return "（无）"
        lines = []
        for item in history[-self.max_history_turns * 2 :]:
            role_value = self._read_field(item, "role")
            content = self._read_field(item, "content")
            role = "用户" if role_value == "user" else "助手"
            lines.append(f"{role}：{content}")
        return "\n".join(lines)

    @staticmethod
    def _read_field(item, key: str, default: str = "") -> str:
        if isinstance(item, dict):
            return str(item.get(key, default) or default)
        try:
            return str(item[key] or default)
        except (KeyError, IndexError, TypeError):
            return default

    def _normalize(self, raw: dict) -> IntentResult:
        intent = str(raw.get("intent", "QUICK_REPLY")).strip().upper()
        if intent not in VALID_INTENTS:
            intent = "QUICK_REPLY"
        intent = cast(IntentType, intent)

        confidence = self._parse_float(raw.get("confidence"), 0.5)
        confidence = max(0.0, min(1.0, confidence))

        risk = str(raw.get("risk_level", "low")).strip().lower()
        if risk not in {"low", "medium", "high"}:
            risk = "low"
        risk = cast(RiskLevel, risk)

        memory_queries = self._parse_string_list(raw.get("memory_queries"), limit=6)
        knowledge_queries = self._parse_string_list(raw.get("knowledge_queries"), limit=6)

        character_id = str(raw.get("character_id", "")).strip()
        expression_id = str(raw.get("expression_id", "")).strip()

        response_mode = str(raw.get("response_mode", "mixed")).strip().lower()
        if response_mode not in VALID_MODES:
            response_mode = "mixed"

        clarify_reply = ""
        if intent == "CLARIFY":
            clarify_reply = str(raw.get("clarify_reply", "")).strip()[:200]

        interaction_type: InteractionType | None = None
        if intent == "INTERACTION":
            raw_type = str(raw.get("interaction_type", "")).strip().lower()
            if raw_type in VALID_INTERACTIONS:
                interaction_type = cast(InteractionType, raw_type)
            else:
                interaction_type = "breathing"

        return IntentResult(
            intent=intent,
            confidence=confidence,
            user_state=str(raw.get("user_state", ""))[:60] or "需要进一步理解",
            core_need=str(raw.get("core_need", ""))[:60] or "被接住",
            emotion=str(raw.get("emotion", ""))[:30] or "未知",
            risk_level=risk,
            memory_queries=memory_queries,
            knowledge_queries=knowledge_queries,
            character_id=character_id,
            expression_id=expression_id,
            response_mode=response_mode,
            response_guidance=str(raw.get("response_guidance", ""))[:140],
            reason=str(raw.get("reason", ""))[:160],
            clarify_reply=clarify_reply,
            interaction_type=interaction_type,
        )

    @staticmethod
    def _parse_float(value, default: float) -> float:
        try:
            return float(value)
        except (TypeError, ValueError):
            return default

    @staticmethod
    def _parse_string_list(value, limit: int = 6) -> list[str]:
        if not isinstance(value, list):
            return []
        results = []
        for item in value:
            text = str(item).strip()[:32]
            if text and text not in results:
                results.append(text)
        return results[:limit]

    def _fallback_result(self, user_text: str) -> IntentResult:
        """当意图识别失败时的安全回退：保守地走深度回复路径。"""
        return IntentResult(
            intent="DEEP_REPLY",
            confidence=0.0,
            user_state="意图识别暂时失败，需要谨慎处理",
            core_need="被稳定地接住",
            emotion="未知",
            risk_level="low",
            memory_queries=[],
            knowledge_queries=[],
            character_id="",
            expression_id="",
            response_mode="mixed",
            response_guidance="先承接用户的话，不急着给结论。",
            reason="意图识别解析失败，回退到安全模式。",
            clarify_reply="",
            interaction_type=None,
        )
