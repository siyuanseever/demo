CRISIS_KEYWORDS = (
    "自杀",
    "轻生",
    "不想活",
    "结束生命",
    "伤害自己",
    "伤害别人",
    "杀了",
    "活不下去",
)


CRISIS_RESPONSE = """我先把安全放在最前面：如果你现在有明确的自伤、轻生或伤害他人的计划，请立刻联系身边可信任的人，或拨打当地紧急电话寻求即时帮助。

我可以继续陪你把此刻的感受说清楚，但我不能替代现实中的危机支持。请先做一件很具体的事：离开可能造成伤害的工具或地点，去到有人在、相对安全的空间里。"""


def detect_crisis(text: str) -> bool:
    return any(keyword in text for keyword in CRISIS_KEYWORDS)

