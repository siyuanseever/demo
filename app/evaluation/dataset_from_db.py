"""
从历史数据库提取对话数据，生成意图识别测试集。

用法：
    python -m app.evaluation.dataset_from_db \
        --db data/app.db \
        --output data/intent_test_set_from_db.jsonl \
        --limit 200

输出格式与 intent_benchmark.py 一致，可直接用于 benchmark。
"""

import argparse
import json
import random
import sqlite3
from pathlib import Path


def fetch_sessions(db_path: str, limit: int = 200) -> list[dict]:
    """
    从数据库中提取最近的对话 session，每轮包含上下文和最终回复。

    Returns:
        每条记录包含：
        - session_id
        - user_text: 用户本轮输入
        - conversation_history: 前序对话
        - assistant_reply: 助手最终回复（用于辅助标注意图）
    """
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()

    # 获取最近的 sessions
    cursor.execute(
        """
        SELECT id FROM sessions
        ORDER BY created_at DESC
        LIMIT ?
        """,
        (limit,),
    )
    sessions = cursor.fetchall()

    results = []
    for session_row in sessions:
        session_id = session_row["id"]
        cursor.execute(
            """
            SELECT role, content, metadata
            FROM messages
            WHERE session_id = ?
            ORDER BY created_at ASC
            """,
            (session_id,),
        )
        messages = cursor.fetchall()

        # 提取用户发言轮次（包含上下文）
        history = []
        for i, msg in enumerate(messages):
            if msg["role"] == "user":
                user_text = msg["content"]
                # 前面最多 5 轮作为上下文
                context_start = max(0, i - 10)
                context = [
                    {"role": m["role"], "content": m["content"]}
                    for m in messages[context_start:i]
                ]
                # 获取助手回复（如果有）
                assistant_reply = ""
                if i + 1 < len(messages) and messages[i + 1]["role"] == "assistant":
                    assistant_reply = messages[i + 1]["content"]

                results.append({
                    "session_id": session_id,
                    "user_text": user_text,
                    "conversation_history": context,
                    "assistant_reply": assistant_reply,
                })

    conn.close()
    return results


def build_dataset(db_path: str, output_path: str, limit: int = 200, sample_size: int | None = None) -> None:
    """
    从数据库提取数据并输出为待标注的测试集模板。

    输出的每条记录包含 expected 字段的骨架，需要人工审核填充正确的意图标签。
    """
    sessions_data = fetch_sessions(db_path, limit=limit)

    if sample_size and len(sessions_data) > sample_size:
        sessions_data = random.sample(sessions_data, sample_size)

    cases = []
    for idx, item in enumerate(sessions_data):
        # 基于助手回复长度做初步意图推测（仅辅助标注，不准确）
        reply_len = len(item["assistant_reply"])
        guessed_intent = "DEEP_REPLY" if reply_len > 150 else "QUICK_REPLY"

        cases.append({
            "id": f"db_{idx:04d}",
            "user_text": item["user_text"],
            "conversation_history": item["conversation_history"],
            "expected": {
                "intent": guessed_intent,
                "risk_level": "low",
                "emotion": "",
            },
            "assistant_reply_preview": item["assistant_reply"][:200],
            "notes": "从数据库提取，需人工标注确认意图和风险等级",
        })

    output = Path(output_path)
    output.parent.mkdir(parents=True, exist_ok=True)
    with output.open("w", encoding="utf-8") as f:
        for case in cases:
            f.write(json.dumps(case, ensure_ascii=False) + "\n")

    print(f"已提取 {len(cases)} 条记录到: {output}")
    print("注意：expected 字段中的意图为基于回复长度的粗略猜测，必须人工审核后使用。")


def main() -> None:
    parser = argparse.ArgumentParser(description="从数据库提取意图识别测试集")
    parser.add_argument("--db", default="data/app.db", help="SQLite 数据库路径")
    parser.add_argument("--output", default="data/intent_test_set_from_db.jsonl", help="输出路径")
    parser.add_argument("--limit", type=int, default=200, help="扫描最近 N 个 session")
    parser.add_argument("--sample", type=int, default=None, help="从中随机采样 N 条")
    args = parser.parse_args()

    build_dataset(args.db, args.output, limit=args.limit, sample_size=args.sample)


if __name__ == "__main__":
    main()
