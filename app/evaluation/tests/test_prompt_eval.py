"""
Prompt 评估器自测

验证 PromptEvaluator 的 JSON 检查、评分计算、用户反馈等核心逻辑。
"""

from app.evaluation.accuracy import AccuracyTest


class PromptEvaluatorAccuracyTest(AccuracyTest):
    """prompt_evaluator 自测"""

    def __init__(self):
        super().__init__("prompt_evaluator", "evaluation.prompt_evaluator")

    def run(self):
        from app.evaluation.prompt_evaluator import PromptEvaluator

        evaluator = PromptEvaluator()

        # 1. _check_json: 合法 JSON
        valid, parsed, err = evaluator._check_json('{"a": 1}')
        self.assert_true("check_json_valid", valid and parsed == {"a": 1} and err == "")

        # 2. _check_json: 带代码块的 JSON
        valid, parsed, err = evaluator._check_json('```json\n{"b": 2}\n```')
        self.assert_true("check_json_codeblock", valid and parsed == {"b": 2})

        # 3. _check_json: 无效 JSON
        valid, parsed, err = evaluator._check_json("not json")
        self.assert_true("check_json_invalid", not valid and parsed is None and bool(err))

        # 4. _check_json: 空字符串
        valid, parsed, err = evaluator._check_json("")
        self.assert_true("check_json_empty", not valid and parsed is None)

        # 5. _check_json: JSON root 为 list 而非 dict
        valid, parsed, err = evaluator._check_json('[1, 2, 3]')
        self.assert_true("check_json_list_root", not valid and "list" in err)

        # 6. _check_json: 多层代码块包裹
        valid, parsed, err = evaluator._check_json('```\n{"nested": true}\n```')
        self.assert_true("check_json_plain_codeblock", valid and parsed == {"nested": True})

        # 7. _calc_overall_score: reply 类型，完美条件
        from app.evaluation.prompt_evaluator import PromptQualityScore
        score = PromptQualityScore(call_id="test_1")
        score.json_valid = True
        score.has_required_fields = True
        score.reply_length = 400
        score.reply_paragraphs = 4
        score.response_time_sec = 3.0
        result = evaluator._calc_overall_score(score, "reply")
        self.assert_true("score_reply_perfect", result >= 90, f"完美 reply 应 >= 90, 实际 {result}")

        # 8. _calc_overall_score: reply 类型，JSON 无效
        score2 = PromptQualityScore(call_id="test_2")
        score2.json_valid = False
        result2 = evaluator._calc_overall_score(score2, "reply")
        self.assert_true("score_reply_no_json", result2 < 50, f"JSON 无效时应 < 50, 实际 {result2}")

        # 9. _calc_overall_score: route_plan 类型
        score3 = PromptQualityScore(call_id="test_3")
        score3.json_valid = True
        score3.has_required_fields = True
        score3.reply_length = 300
        score3.reply_paragraphs = 3
        score3.response_time_sec = 2.0
        result3 = evaluator._calc_overall_score(score3, "route_plan")
        self.assert_true("score_route_plan", result3 >= 80, f"route_plan 应 >= 80, 实际 {result3}")

        # 10. _calc_overall_score: home_hint 类型
        score4 = PromptQualityScore(call_id="test_4")
        score4.reply_length = 35
        score4.response_time_sec = 1.5
        result4 = evaluator._calc_overall_score(score4, "home_hint")
        self.assert_true("score_home_hint", result4 >= 60, f"home_hint 应 >= 60, 实际 {result4}")

        # 11. _calc_overall_score: 未知类型，默认分支
        score5 = PromptQualityScore(call_id="test_5")
        score5.json_valid = True
        result5 = evaluator._calc_overall_score(score5, "unknown_type")
        self.assert_true("score_unknown", result5 == 70.0, f"未知类型默认 70, 实际 {result5}")

        # 12. add_user_feedback: 正常评分
        evaluator.add_user_feedback("test_fb_1", 4, "不错")
        summary = evaluator.get_summary()
        self.assert_true("feedback_added", summary["user_rated_count"] >= 1)

        # 13. add_user_feedback: 边界值（超过 5 星应截断）
        evaluator.add_user_feedback("test_fb_2", 10)
        scores = evaluator.to_dict_list(limit=10)
        fb2 = [s for s in scores if s["call_id"] == "test_fb_2"]
        if fb2:
            self.assert_true("feedback_clamped", fb2[0]["user_rating"] == 5, "评分应被截断到 5")

        # 14. add_user_feedback: 边界值（低于 1 星应截断）
        evaluator.add_user_feedback("test_fb_3", 0)
        scores = evaluator.to_dict_list(limit=10)
        fb3 = [s for s in scores if s["call_id"] == "test_fb_3"]
        if fb3:
            self.assert_true("feedback_floor", fb3[0]["user_rating"] == 1, "评分应被截断到 1")

        # 15. get_summary: 空评估器
        empty_eval = PromptEvaluator()
        empty_summary = empty_eval.get_summary()
        self.assert_true("empty_summary", empty_summary["total_evaluated"] == 0)

        return self.results


def get_prompt_eval_tests() -> list[AccuracyTest]:
    """返回 Prompt 评估器自测实例"""
    return [PromptEvaluatorAccuracyTest()]
