import unittest

from app.agents.orchestrator import render_memories


class RenderMemoriesTest(unittest.TestCase):
    def test_renders_list_keywords_and_string_evidence(self) -> None:
        rendered = render_memories(
            [
                {
                    "category": "emotion",
                    "subcategory": "anxiety",
                    "content": "最近容易焦虑",
                    "keywords": ["焦虑", "睡眠"],
                    "evidence": "用户近期自述",
                }
            ]
        )

        self.assertIn("关键词：焦虑、睡眠", rendered)
        self.assertIn("证据：用户近期自述", rendered)

    def test_normalizes_serialized_keywords_and_list_evidence(self) -> None:
        rendered = render_memories(
            [
                {
                    "category": "relationship",
                    "subcategory": "family",
                    "content": "家庭互动带来压力",
                    "keywords": '["家庭", 2]',
                    "evidence": ["记录一", "记录二"],
                }
            ]
        )

        self.assertIn("关键词：家庭、2", rendered)
        self.assertIn("证据：记录一、记录二", rendered)

    def test_tolerates_invalid_optional_fields(self) -> None:
        rendered = render_memories(
            [
                {
                    "category": "other",
                    "subcategory": "other",
                    "content": "一条记忆",
                    "keywords": '{"not": "a list"}',
                }
            ]
        )

        self.assertIn("关键词：；证据：", rendered)


if __name__ == "__main__":
    unittest.main()
