"""Build a private, local-only response-value evaluation set from SQLite."""

from __future__ import annotations

import argparse
import json
import sqlite3
from collections import Counter, defaultdict
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any


THEMES: dict[str, tuple[str, ...]] = {
    "career_work": ("工作", "求职", "面试", "公司", "岗位", "简历", "上班", "职业", "领导", "工资"),
    "relationship_connection": ("小宝", "花花", "关系", "回复", "联系", "朋友", "喜欢", "感情", "约", "陪"),
    "dreams_learning": ("梦", "学习", "数学", "考试", "论文", "文档", "课程", "知识", "研究", "教条"),
    "family_boundaries": ("爸爸", "父亲", "妈妈", "母亲", "家里", "家庭", "要钱", "边界", "拒绝", "房东"),
    "body_energy": ("身体", "累", "疲惫", "睡", "疼", "药", "紧绷", "头晕", "休息", "能量"),
    "loneliness_emotion": ("孤独", "难过", "失落", "焦虑", "害怕", "痛苦", "情绪", "不开心", "愤怒", "无力"),
    "self_worth_identity": ("价值", "自卑", "失败", "不够好", "证明", "评价", "自我", "尊严", "能力", "被看轻"),
    "creativity_agent": ("agent", "Agent", "Claude", "Codex", "创作", "写作", "知乎", "设计", "开发", "产品"),
}

THEME_LABELS = {
    "career_work": "求职与工作",
    "relationship_connection": "关系与连接",
    "dreams_learning": "梦境与学习",
    "family_boundaries": "家庭与边界",
    "body_energy": "身体与能量",
    "loneliness_emotion": "孤独与情绪",
    "self_worth_identity": "自我价值",
    "creativity_agent": "创作与 Agent",
    "other": "其他",
}

DIMENSIONS = [
    ("understanding", "被理解", "是否准确指出真正卡住的地方，而非简单复述"),
    ("information_gain", "信息增量", "是否带来了用户原先没有明确说出的新结构"),
    ("hidden_structure", "隐藏结构", "是否发现矛盾、模式、因果或跨时间联系"),
    ("memory_use", "记忆使用", "历史信息是否相关、准确，并真正参与推理"),
    ("personalized_action", "行动价值", "建议是否具体、个性化、适合此刻"),
    ("low_cliche", "避免套话", "是否避免空泛安慰、万能建议和语言填充"),
    ("continue_desire", "继续交流意愿", "看完后是否让人愿意继续说下去"),
]

FAILURE_TYPES = [
    "只有复述",
    "空泛安慰",
    "万能建议",
    "编造或误用记忆",
    "过度心理解释",
    "诊断化表达",
    "强行积极",
    "过长但没有增量",
]


@dataclass
class Turn:
    id: str
    session_id: str
    user_message_id: str
    created_at: str
    user_text: str
    context: list[dict[str, str]]
    responses: list[dict[str, Any]]
    themes: list[str]
    route_plan: dict[str, Any]
    memory_ids: list[str]
    knowledge_card_ids: list[str]
    evaluation_theme: str = "other"

    @property
    def quality_weight(self) -> float:
        length_score = min(len(self.user_text), 900) / 180
        response_score = min(sum(len(item["text"]) for item in self.responses), 1800) / 450
        deep_bonus = 1.5 if any(item["stage"] == "deep" for item in self.responses) else 0
        memory_bonus = min(len(self.memory_ids), 3) * 0.4
        return length_score + response_score + deep_bonus + memory_bonus


def _parse_metadata(raw: str) -> dict[str, Any]:
    try:
        value = json.loads(raw or "{}")
    except json.JSONDecodeError:
        return {}
    return value if isinstance(value, dict) else {}


def _classify_themes(text: str) -> list[str]:
    scored = []
    for theme, keywords in THEMES.items():
        score = sum(text.count(keyword) for keyword in keywords)
        if score:
            scored.append((score, theme))
    scored.sort(key=lambda item: (-item[0], item[1]))
    return [theme for _, theme in scored[:2]] or ["other"]


def _response_stage(metadata: dict[str, Any], index: int) -> str:
    stage = str(metadata.get("reply_stage") or "").strip().lower()
    if stage in {"quick", "deep"}:
        return stage
    group_role = str(metadata.get("group_role") or "").strip().lower()
    if group_role:
        return group_role
    return "reply" if index == 0 else f"reply_{index + 1}"


def load_turns(db_path: Path) -> list[Turn]:
    connection = sqlite3.connect(db_path)
    connection.row_factory = sqlite3.Row
    rows = connection.execute(
        """
        SELECT id, session_id, role, content, model, metadata, created_at
        FROM messages
        ORDER BY session_id, created_at, rowid
        """
    ).fetchall()
    connection.close()

    sessions: dict[str, list[sqlite3.Row]] = defaultdict(list)
    for row in rows:
        sessions[row["session_id"]].append(row)

    turns: list[Turn] = []
    for session_id, messages in sessions.items():
        for index, message in enumerate(messages):
            if message["role"] != "user":
                continue
            assistant_rows = []
            cursor = index + 1
            while cursor < len(messages) and messages[cursor]["role"] != "user":
                if messages[cursor]["role"] == "assistant":
                    assistant_rows.append(messages[cursor])
                cursor += 1
            if not assistant_rows:
                continue

            responses = []
            route_plan: dict[str, Any] = {}
            memory_ids: list[str] = []
            knowledge_card_ids: list[str] = []
            for response_index, assistant in enumerate(assistant_rows):
                metadata = _parse_metadata(assistant["metadata"])
                if not route_plan and isinstance(metadata.get("route_plan"), dict):
                    route_plan = metadata["route_plan"]
                raw_memory_ids = metadata.get("memory_ids") or metadata.get("retrieved_memory_ids") or []
                if isinstance(raw_memory_ids, list):
                    memory_ids.extend(str(item) for item in raw_memory_ids if item)
                raw_card_ids = metadata.get("knowledge_card_ids") or []
                if isinstance(raw_card_ids, list):
                    knowledge_card_ids.extend(str(item) for item in raw_card_ids if item)
                responses.append(
                    {
                        "message_id": assistant["id"],
                        "stage": _response_stage(metadata, response_index),
                        "text": assistant["content"],
                        "model": assistant["model"] or "",
                        "reply_group_id": metadata.get("reply_group_id") or "",
                    }
                )

            context_start = max(0, index - 4)
            context = [
                {"role": item["role"], "text": item["content"]}
                for item in messages[context_start:index]
                if item["role"] in {"user", "assistant"}
            ]
            user_text = message["content"].strip()
            if not user_text or user_text.startswith("/"):
                continue
            turns.append(
                Turn(
                    id=f"rv-{message['id']}",
                    session_id=session_id,
                    user_message_id=message["id"],
                    created_at=message["created_at"],
                    user_text=user_text,
                    context=context,
                    responses=responses,
                    themes=_classify_themes(user_text),
                    route_plan=route_plan,
                    memory_ids=list(dict.fromkeys(memory_ids)),
                    knowledge_card_ids=list(dict.fromkeys(knowledge_card_ids)),
                )
            )
    return turns


def select_candidates(turns: list[Turn], count: int = 24) -> list[Turn]:
    eligible = [
        turn
        for turn in turns
        if len(turn.user_text) >= 35
        and any(len(response["text"].strip()) >= 20 for response in turn.responses)
    ]
    by_theme: dict[str, list[Turn]] = defaultdict(list)
    for turn in eligible:
        for theme in turn.themes:
            by_theme[theme].append(turn)
    for values in by_theme.values():
        values.sort(key=lambda turn: (-turn.quality_weight, turn.created_at, turn.id))

    selected: list[Turn] = []
    selected_ids: set[str] = set()
    session_counts: Counter[str] = Counter()
    theme_order = list(THEMES)
    target_per_theme = max(1, count // len(theme_order))

    for theme in theme_order:
        added = 0
        for turn in by_theme.get(theme, []):
            if turn.id in selected_ids or session_counts[turn.session_id] >= 2:
                continue
            selected.append(turn)
            turn.evaluation_theme = theme
            selected_ids.add(turn.id)
            session_counts[turn.session_id] += 1
            added += 1
            if added >= target_per_theme or len(selected) >= count:
                break

    if len(selected) < count:
        remaining = sorted(eligible, key=lambda turn: (-turn.quality_weight, turn.created_at, turn.id))
        for turn in remaining:
            if turn.id in selected_ids or session_counts[turn.session_id] >= 2:
                continue
            selected.append(turn)
            turn.evaluation_theme = turn.themes[0]
            selected_ids.add(turn.id)
            session_counts[turn.session_id] += 1
            if len(selected) >= count:
                break

    selected.sort(key=lambda turn: (turn.evaluation_theme, turn.created_at, turn.id))
    return selected


def _scorecard_html(cases: list[dict[str, Any]]) -> str:
    payload = json.dumps(cases, ensure_ascii=False).replace("</", "<\\/")
    dimensions = json.dumps(DIMENSIONS, ensure_ascii=False)
    failure_types = json.dumps(FAILURE_TYPES, ensure_ascii=False)
    return f"""<!doctype html>
<html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>回复价值评分</title><style>
:root{{--bg:#f6f1eb;--card:#fffdf9;--ink:#403733;--muted:#7d716c;--line:#e6d9cf;--accent:#8b6f9e;--soft:#efe7f3}}
*{{box-sizing:border-box}}body{{margin:0;background:var(--bg);color:var(--ink);font:15px/1.65 -apple-system,BlinkMacSystemFont,"PingFang SC",sans-serif}}
header{{position:sticky;top:0;z-index:5;padding:18px 28px;background:rgba(246,241,235,.94);backdrop-filter:blur(14px);border-bottom:1px solid var(--line)}}
.header-row{{display:flex;gap:16px;align-items:center;flex-wrap:wrap}}h1{{font-size:22px;margin:0}}.muted{{color:var(--muted)}}
button,select{{font:inherit}}button{{border:0;border-radius:12px;padding:9px 14px;background:var(--accent);color:white;cursor:pointer}}
main{{max-width:1080px;margin:24px auto;padding:0 20px 80px}}.case{{background:var(--card);border:1px solid var(--line);border-radius:20px;padding:22px;margin:18px 0;box-shadow:0 8px 30px rgba(70,48,40,.05)}}
.case-head{{display:flex;justify-content:space-between;gap:12px;align-items:flex-start}}.tag{{display:inline-block;padding:3px 9px;border-radius:999px;background:var(--soft);color:#715781;font-size:12px;margin-right:6px}}
.text-block{{white-space:pre-wrap;padding:14px 16px;border-radius:14px;background:#faf6f1;margin:10px 0}}.response{{border-left:3px solid #c7afd2}}details{{margin:10px 0}}summary{{cursor:pointer;color:var(--muted)}}
.dimension{{display:grid;grid-template-columns:minmax(150px,1fr) 210px;gap:14px;padding:10px 0;border-top:1px solid #eee5de}}.dimension small{{display:block;color:var(--muted)}}
.options{{display:flex;gap:6px;justify-content:flex-end}}.options label{{cursor:pointer;padding:6px 10px;border:1px solid var(--line);border-radius:10px}}.options label:has(input:checked){{background:var(--soft);border-color:#b79ac5}}input[type=radio]{{display:none}}
.failures{{display:flex;flex-wrap:wrap;gap:8px}}.failures label{{padding:5px 9px;border-radius:9px;background:#f8efed}}textarea{{width:100%;min-height:74px;border:1px solid var(--line);border-radius:12px;padding:10px;font:inherit;background:white}}
.progress{{font-variant-numeric:tabular-nums}}@media(max-width:700px){{.dimension{{grid-template-columns:1fr}}.options{{justify-content:flex-start}}}}
</style></head><body>
<header><div class="header-row"><div><h1>回复价值评分</h1><div class="muted">0=没有，1=有一点，2=明确有价值。评分自动保存在当前浏览器。</div></div><span class="progress" id="progress"></span><select id="themeFilter"><option value="">全部主题</option></select><button id="export">导出评分 JSON</button></div></header>
<main id="cases"></main>
<script>const cases={payload};const dimensions={dimensions};const failureTypes={failure_types};
const storageKey='sensen-response-value-v1';let scores=JSON.parse(localStorage.getItem(storageKey)||'{{}}');
const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({{'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}}[c]));
const themeNames={json.dumps(THEME_LABELS, ensure_ascii=False)};
function save(){{localStorage.setItem(storageKey,JSON.stringify(scores));updateProgress()}}
function updateProgress(){{const done=cases.filter(c=>dimensions.every(d=>scores[c.id]?.dimensions?.[d[0]]!==undefined)).length;document.querySelector('#progress').textContent=`已完成 ${{done}} / ${{cases.length}}`}}
function render(){{const filter=document.querySelector('#themeFilter').value;const root=document.querySelector('#cases');root.innerHTML='';cases.filter(c=>!filter||c.evaluation_theme===filter).forEach((c,i)=>{{const state=scores[c.id]||{{dimensions:{{}},failures:[],notes:''}};const article=document.createElement('article');article.className='case';article.innerHTML=`
<div class="case-head"><div><strong>${{esc(c.id)}}</strong><div><span class="tag">主类：${{esc(themeNames[c.evaluation_theme]||c.evaluation_theme)}}</span>${{c.themes.filter(t=>t!==c.evaluation_theme).map(t=>`<span class="tag">${{esc(themeNames[t]||t)}}</span>`).join('')}}</div></div><span class="muted">${{esc(c.created_at.slice(0,10))}} · ${{c.responses.length}} 条回复</span></div>
<h2>用户输入</h2><div class="text-block">${{esc(c.user_text)}}</div>
${{c.context.length?`<details><summary>查看前序上下文（${{c.context.length}} 条）</summary>${{c.context.map(x=>`<div class="text-block"><b>${{x.role==='user'?'用户':'小兔子'}}</b>：${{esc(x.text)}}</div>`).join('')}}</details>`:''}}
<h2>当前回复</h2>${{c.responses.map(r=>`<div class="text-block response"><span class="tag">${{esc(r.stage)}}</span>${{esc(r.text)}}</div>`).join('')}}
<details><summary>查看原有 route plan 与引用 ID</summary><pre class="text-block">${{esc(JSON.stringify({{route_plan:c.route_plan,memory_ids:c.memory_ids,knowledge_card_ids:c.knowledge_card_ids}},null,2))}}</pre></details>
<h2>你的评分</h2>${{dimensions.map(d=>`<div class="dimension"><div><b>${{d[1]}}</b><small>${{d[2]}}</small></div><div class="options">${{[0,1,2].map(v=>`<label><input type="radio" name="${{c.id}}-${{d[0]}}" value="${{v}}" ${{state.dimensions?.[d[0]]===v?'checked':''}}> ${{v}}</label>`).join('')}}</div></div>`).join('')}}
<h3>失败类型</h3><div class="failures">${{failureTypes.map(f=>`<label><input type="checkbox" value="${{esc(f)}}" ${{state.failures?.includes(f)?'checked':''}}> ${{esc(f)}}</label>`).join('')}}</div>
<h3>备注</h3><textarea placeholder="哪一句有价值？哪里像套话？你真正希望它说什么？">${{esc(state.notes||'')}}</textarea>`;
article.addEventListener('change',e=>{{scores[c.id]=scores[c.id]||{{dimensions:{{}},failures:[],notes:''}};if(e.target.type==='radio'){{const key=e.target.name.slice(c.id.length+1);scores[c.id].dimensions[key]=Number(e.target.value)}}else if(e.target.type==='checkbox'){{scores[c.id].failures=[...article.querySelectorAll('.failures input:checked')].map(x=>x.value)}}save()}});
article.querySelector('textarea').addEventListener('input',e=>{{scores[c.id]=scores[c.id]||{{dimensions:{{}},failures:[],notes:''}};scores[c.id].notes=e.target.value;save()}});root.appendChild(article)}});updateProgress()}}
const allThemes=[...new Set(cases.map(c=>c.evaluation_theme))];const filter=document.querySelector('#themeFilter');allThemes.forEach(t=>{{const o=document.createElement('option');o.value=t;o.textContent=themeNames[t]||t;filter.appendChild(o)}});filter.addEventListener('change',render);
document.querySelector('#export').addEventListener('click',()=>{{const out={{generated_at:new Date().toISOString(),dataset_version:'response-value-v1',scores}};const blob=new Blob([JSON.stringify(out,null,2)],{{type:'application/json'}});const a=document.createElement('a');a.href=URL.createObjectURL(blob);a.download='response_value_scores.json';a.click();URL.revokeObjectURL(a.href)}});render();</script></body></html>"""


def write_dataset(candidates: list[Turn], output_dir: Path) -> dict[str, Any]:
    output_dir.mkdir(parents=True, exist_ok=True)
    cases = [asdict(candidate) for candidate in candidates]
    jsonl_path = output_dir / "candidates.jsonl"
    jsonl_path.write_text(
        "".join(json.dumps(case, ensure_ascii=False) + "\n" for case in cases),
        encoding="utf-8",
    )
    scorecard_path = output_dir / "scorecard.html"
    scorecard_path.write_text(_scorecard_html(cases), encoding="utf-8")
    theme_counts = Counter(case.evaluation_theme for case in candidates)
    manifest = {
        "dataset_version": "response-value-v1",
        "candidate_count": len(candidates),
        "theme_counts": dict(sorted(theme_counts.items())),
        "session_count": len({case.session_id for case in candidates}),
        "privacy": "local_only_private_text_not_for_git_or_logs",
        "files": {"cases": str(jsonl_path), "scorecard": str(scorecard_path)},
    }
    (output_dir / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    return manifest


def main() -> None:
    parser = argparse.ArgumentParser(description="生成本地私密回复价值评分集")
    parser.add_argument("--db", default="data/app.db")
    parser.add_argument("--output-dir", default="data/response_value")
    parser.add_argument("--count", type=int, default=24)
    args = parser.parse_args()

    turns = load_turns(Path(args.db))
    candidates = select_candidates(turns, count=max(1, args.count))
    manifest = write_dataset(candidates, Path(args.output_dir))
    print(json.dumps(manifest, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
