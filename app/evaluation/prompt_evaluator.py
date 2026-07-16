"""
Prompt 效果评估框架

评估维度：
- 响应格式正确性 (JSON 有效性、schema 匹配)
- 回复质量评分 (长度、结构、角色一致性)
- 记忆提取准确率
- Prompt 效率指标 (token 使用、响应时间)
- 用户反馈 (thumbs up/down)
"""

import json
import time
import threading
from dataclasses import dataclass, field, asdict
from pathlib import Path
from typing import Any

from app.evaluation.prompt_tracker import PromptTracker


@dataclass
class PromptQualityScore:
    """单次 Prompt 调用质量评分"""
    call_id: str
    # 格式正确性
    json_valid: bool = False
    json_parse_error: str = ""
    has_required_fields: bool = False
    missing_fields: list[str] = field(default_factory=list)

    # 内容质量
    reply_length: int = 0
    reply_paragraphs: int = 0
    has_emoji_or_action: bool = False

    # 效率指标
    prompt_tokens_est: int = 0
    response_tokens_est: int = 0
    response_time_sec: float = 0.0
    tokens_per_sec: float = 0.0

    # 用户反馈
    user_rating: int | None = None  # 1-5 星，None 表示未评价
    user_feedback: str = ""

    # 综合得分 0-100
    overall_score: float = 0.0


class PromptEvaluator:
    """Prompt 效果评估器"""

    def __init__(self, tracker: PromptTracker | None = None):
        self.tracker = tracker or PromptTracker()
        self._scores: dict[str, PromptQualityScore] = {}
        self._lock = threading.Lock()
        self._storage_dir = Path("data/prompt_logs")
        self._storage_dir.mkdir(parents=True, exist_ok=True)

    def evaluate_call(self, call_id: str, required_fields: list[str] | None = None) -> PromptQualityScore:
        """评估指定 call_id 的 prompt 质量"""
        record = self.tracker.get_record(call_id)
        if not record:
            return PromptQualityScore(call_id=call_id, overall_score=0)

        score = PromptQualityScore(call_id=call_id)
        score.prompt_tokens_est = record.prompt_tokens_est
        score.response_tokens_est = record.response_tokens_est
        score.response_time_sec = record.response_time_sec

        content = record.response_content or ""

        # 1. JSON 有效性评估
        if record.call_type in ("reply", "route_plan", "memory_extract", "memory_merge"):
            score.json_valid, parsed, score.json_parse_error = self._check_json(content)
            if score.json_valid and parsed and required_fields:
                score.missing_fields = [f for f in required_fields if f not in parsed]
                score.has_required_fields = len(score.missing_fields) == 0
            elif score.json_valid and parsed:
                score.has_required_fields = True

        # 2. 内容质量评估
        score.reply_length = len(content)
        score.reply_paragraphs = content.count("\n\n") + 1
        score.has_emoji_or_action = "(" in content or ")" in content or any(
            ord(c) > 0x1F300 for c in content
        )

        # 3. 效率指标
        if score.response_time_sec > 0:
            score.tokens_per_sec = round(
                (score.prompt_tokens_est + score.response_tokens_est) / score.response_time_sec, 1
            )

        # 4. 综合得分计算
        score.overall_score = self._calc_overall_score(score, record.call_type)

        with self._lock:
            self._scores[call_id] = score
            self._persist_score(score)

        return score

    def _check_json(self, content: str) -> tuple[bool, dict | None, str]:
        """检查 JSON 有效性"""
        text = content.strip()
        if text.startswith("```"):
            lines = text.splitlines()
            if lines and lines[0].startswith("```"):
                lines = lines[1:]
            if lines and lines[-1].strip() == "```":
                lines = lines[:-1]
            text = "\n".join(lines).strip()
        try:
            parsed = json.loads(text)
            if isinstance(parsed, dict):
                return True, parsed, ""
            return False, None, f"JSON root is {type(parsed).__name__}, expected dict"
        except json.JSONDecodeError as e:
            return False, None, str(e)
        except Exception as e:
            return False, None, str(e)

    def _calc_overall_score(self, score: PromptQualityScore, call_type: str) -> float:
        """计算综合得分 0-100"""
        if call_type in ("reply", "route_plan"):
            # JSON 格式: 30 分
            json_score = 30 if score.json_valid else 0
            # 必填字段: 20 分
            fields_score = 20 if score.has_required_fields else 0
            # 回复长度: 20 分（150-800 字为宜）
            length_score = 0
            if 150 <= score.reply_length <= 800:
                length_score = 20
            elif score.reply_length > 0:
                length_score = min(20, max(5, 20 - abs(score.reply_length - 475) / 50))
            # 响应时间: 15 分（<5s 满分）
            time_score = 15 if score.response_time_sec < 5 else max(0, 15 - (score.response_time_sec - 5) / 2)
            # 段落结构: 15 分
            para_score = 15 if 2 <= score.reply_paragraphs <= 10 else 5

            return round(json_score + fields_score + length_score + time_score + para_score, 1)

        elif call_type == "home_hint":
            # 首页提示：长度 20-50 字，一句话
            length_score = 30 if 20 <= score.reply_length <= 50 else 10
            time_score = 30 if score.response_time_sec < 3 else 15
            return round(length_score + time_score + 40, 1)

        else:
            # 其他类型：基础分
            return 70.0 if score.json_valid else 50.0

    def add_user_feedback(self, call_id: str, rating: int, feedback: str = "") -> None:
        """添加用户反馈（1-5 星）"""
        with self._lock:
            score = self._scores.get(call_id)
            if not score:
                score = PromptQualityScore(call_id=call_id)
                self._scores[call_id] = score
            score.user_rating = max(1, min(5, rating))
            score.user_feedback = feedback
            self._persist_score(score)

    def evaluate_all(self) -> list[PromptQualityScore]:
        """评估所有未评估的调用记录"""
        records = self.tracker.get_records(limit=200)
        results = []
        for record in records:
            with self._lock:
                if record.call_id in self._scores:
                    continue
            results.append(self.evaluate_call(record.call_id))
        return results

    def get_summary(self) -> dict[str, Any]:
        """获取评估汇总"""
        with self._lock:
            scores = list(self._scores.values())

        if not scores:
            return {"total_evaluated": 0}

        avg_score = sum(s.overall_score for s in scores) / len(scores)
        json_valid_rate = sum(1 for s in scores if s.json_valid) / len(scores)
        has_rating = [s for s in scores if s.user_rating is not None]
        avg_user_rating = sum(s.user_rating for s in has_rating if s.user_rating is not None) / len(has_rating) if has_rating else 0

        return {
            "total_evaluated": len(scores),
            "avg_overall_score": round(avg_score, 1),
            "json_valid_rate": round(json_valid_rate * 100, 1),
            "avg_response_time_sec": round(sum(s.response_time_sec for s in scores) / len(scores), 2),
            "avg_prompt_tokens": round(sum(s.prompt_tokens_est for s in scores) / len(scores), 1),
            "avg_response_tokens": round(sum(s.response_tokens_est for s in scores) / len(scores), 1),
            "user_rated_count": len(has_rating),
            "avg_user_rating": round(avg_user_rating, 1) if has_rating else None,
        }

    def _persist_score(self, score: PromptQualityScore) -> None:
        """持久化评分到 JSONL"""
        date_str = time.strftime("%Y%m%d")
        path = self._storage_dir / f"prompt_scores_{date_str}.jsonl"
        with open(path, "a", encoding="utf-8") as f:
            f.write(json.dumps(asdict(score), ensure_ascii=False) + "\n")

    def to_dict_list(self, limit: int = 100) -> list[dict]:
        with self._lock:
            scores = list(self._scores.values())
        return [asdict(s) for s in scores[-limit:]]
