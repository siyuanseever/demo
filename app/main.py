from app.agents.orchestrator import ConversationOrchestrator
from app.config import get_settings
from app.llm.deepseek import DeepSeekClient
from app.memory.store import Store


def build_orchestrator() -> ConversationOrchestrator:
    settings = get_settings()
    if not settings.deepseek_api_key:
        raise SystemExit(
            "缺少 DEEPSEEK_API_KEY。请复制 .env.example 为 .env，或在 shell 中 export。"
        )
    llm = DeepSeekClient(
        api_key=settings.deepseek_api_key,
        model=settings.deepseek_model,
        base_url=settings.deepseek_base_url,
    )
    store = Store(settings.app_db_path)
    return ConversationOrchestrator(llm=llm, store=store)


def main() -> None:
    orchestrator = build_orchestrator()
    session_id = orchestrator.start_session()
    print("心理陪伴 Agent Demo")
    print("输入 /end 结束并生成 journal + memories；输入 /quit 直接退出。")

    while True:
        try:
            user_text = input("\n你：").strip()
        except (EOFError, KeyboardInterrupt):
            print("\n已退出，当前会话未总结。")
            return

        if not user_text:
            continue
        if user_text == "/quit":
            print("已退出，当前会话未总结。")
            return
        if user_text == "/end":
            result = orchestrator.close_session(session_id)
            print("\n会话总结：")
            print(result["journal"].get("summary", ""))
            print("\n新增记忆：")
            for memory in result["memories"]:
                print(f"- [{memory['category']}] {memory['content']}")
            return

        assistant_text = orchestrator.reply(session_id, user_text)
        print(f"\n陪伴者：{assistant_text}")


if __name__ == "__main__":
    main()

