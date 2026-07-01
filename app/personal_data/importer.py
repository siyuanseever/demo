import hashlib
import json
import logging
import os
import re
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from app.memory.schema import MEMORY_CATEGORIES, MENTAL_STATUS_MOODS
from app.memory.store import Store


LOGGER = logging.getLogger(__name__)

DEFAULT_DIARY_ROOT = (
    Path.home()
    / "Library/Mobile Documents/iCloud~md~obsidian/Documents/psychevia/write/diary/private"
)

PROMPT_DIR = Path(__file__).resolve().parents[1] / "prompts"

DIARY_SOURCE_SESSION_PREFIX = "diary-import-"


def _file_hash(path: Path) -> str:
    h = hashlib.sha256()
    h.update(path.read_bytes())
    return h.hexdigest()[:32]


def _parse_date_from_filename(name: str) -> str | None:
    # YYYYMMDD.
    m = re.match(r"^(\d{4})(\d{2})(\d{2})\.", name)
    if m:
        return f"{m.group(1)}-{m.group(2)}-{m.group(3)}"
    m = re.search(r"(\d{4})(\d{2})(\d{2})", name)
    if m:
        return f"{m.group(1)}-{m.group(2)}-{m.group(3)}"
    # YYYYMM. — use 01 as day fallback
    m = re.match(r"^(\d{4})(\d{2})\.", name)
    if m:
        return f"{m.group(1)}-{m.group(2)}-01"
    m = re.search(r"(\d{4})(\d{2})(?:\D)", name)
    if m:
        return f"{m.group(1)}-{m.group(2)}-01"
    return None


def _read_prompt(name: str) -> str:
    return (PROMPT_DIR / name).read_text(encoding="utf-8")


def _parse_json_object(content: str) -> dict:
    text = str(content or "").strip()
    if not text:
        return {}
    try:
        payload = json.loads(text)
    except json.JSONDecodeError:
        start = text.find("{")
        end = text.rfind("}")
        if start < 0 or end <= start:
            return {}
        try:
            payload = json.loads(text[start : end + 1])
        except json.JSONDecodeError:
            return {}
    if not isinstance(payload, dict):
        return {}
    return payload


def _extract_diary_text(content: str) -> str:
    text = re.sub(r"^---\n.*?---\n", "", content, flags=re.DOTALL)
    return text.strip()


def call_llm_for_diary(
    llm: Any,
    text: str,
    filename: str = "",
) -> dict[str, Any] | None:
    """Call LLM to extract both mental status and long-term memories from a diary entry."""
    prompt = _read_prompt("diary_memory_extract.md").format(
        moods="、".join(MENTAL_STATUS_MOODS),
        categories="、".join(MEMORY_CATEGORIES),
    )
    context = text
    if filename:
        context = f"文件：{filename}\n\n{context}"
    try:
        response = llm.chat(
            [
                {"role": "system", "content": prompt},
                {"role": "user", "content": context},
            ],
            temperature=0.3,
            max_tokens=1200,
            response_format={"type": "json_object"},
        )
        result = _parse_json_object(response.content)
        if not result.get("mental_status") and not result.get("memories"):
            LOGGER.warning("LLM returned empty result for %s", filename)
            return None
        return result
    except Exception:
        LOGGER.exception("LLM call failed for %s", filename)
        return None


class DiaryImporter:
    def __init__(
        self,
        store: Store,
        llm: Any,
        diary_root: Path | None = None,
    ) -> None:
        self.store = store
        self.llm = llm
        self.diary_root = diary_root or DEFAULT_DIARY_ROOT

    def scan_diary_files(self) -> list[Path]:
        if not self.diary_root.exists():
            LOGGER.warning("diary root not found: %s", self.diary_root)
            return []
        files = []
        for subdir in sorted(self.diary_root.iterdir()):
            if not subdir.is_dir():
                continue
            for file_path in sorted(subdir.iterdir()):
                if file_path.suffix.lower() == ".md":
                    files.append(file_path)
        LOGGER.info("scanned %d diary files from %s", len(files), self.diary_root)
        return files

    def _upsert_source(
        self,
        file_path: Path,
        file_hash: str,
        record_ids: list[str],
        memory_ids: list[str],
        record_date: str,
    ) -> None:
        now = datetime.now(timezone.utc).isoformat()
        with self.store.connect() as conn:
            existing = conn.execute(
                "SELECT id FROM user_document_sources WHERE file_path = ?",
                (str(file_path),),
            ).fetchone()
            if existing:
                conn.execute(
                    """
                    UPDATE user_document_sources
                    SET file_hash = ?, last_imported_at = ?, document_date = ?,
                        extracted_record_ids = ?, extracted_memory_ids = ?
                    WHERE id = ?
                    """,
                    (
                        file_hash,
                        now,
                        record_date,
                        json.dumps(record_ids, ensure_ascii=False),
                        json.dumps(memory_ids, ensure_ascii=False),
                        existing["id"],
                    ),
                )
            else:
                conn.execute(
                    """
                    INSERT INTO user_document_sources
                    (id, source_type, file_path, file_hash, extracted_record_ids,
                     extracted_memory_ids, last_imported_at, document_date)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    (
                        str(os.urandom(16).hex()),
                        "diary",
                        str(file_path),
                        file_hash,
                        json.dumps(record_ids, ensure_ascii=False),
                        json.dumps(memory_ids, ensure_ascii=False),
                        now,
                        record_date,
                    ),
                )

    def import_diaries(
        self,
        dry_run: bool = False,
        delay_between_calls: float = 1.0,
        limit: int | None = None,
    ) -> dict[str, Any]:
        files = self.scan_diary_files()
        if limit:
            files = files[:limit]
        imported_count = 0
        skipped_count = 0
        error_count = 0
        total_memories = 0
        total_records = 0

        for idx, file_path in enumerate(files, 1):
            try:
                file_hash = _file_hash(file_path)

                with self.store.connect() as conn:
                    existing = conn.execute(
                        "SELECT id, file_hash FROM user_document_sources WHERE file_path = ?",
                        (str(file_path),),
                    ).fetchone()

                if existing and existing["file_hash"] == file_hash:
                    skipped_count += 1
                    continue

                record_date = _parse_date_from_filename(file_path.name)
                if not record_date:
                    mtime = datetime.fromtimestamp(file_path.stat().st_mtime, tz=timezone.utc)
                    record_date = mtime.date().isoformat()
                    LOGGER.info("date fallback to mtime for %s: %s", file_path.name, record_date)

                content = file_path.read_text(encoding="utf-8")
                text = _extract_diary_text(content)
                if not text:
                    LOGGER.info("empty text after extraction: %s", file_path.name)
                    skipped_count += 1
                    continue

                LOGGER.info(
                    "[%d/%d] calling LLM for: %s",
                    idx, len(files), file_path.name,
                )

                result = call_llm_for_diary(
                    self.llm, text, filename=file_path.name,
                )
                if not result:
                    LOGGER.warning("LLM returned nothing for: %s", file_path.name)
                    error_count += 1
                    continue

                # Extract mental status record
                mental_status = result.get("mental_status", {})
                if mental_status.get("mood"):
                    status_record = {
                        "record_date": record_date,
                        "record_time": None,
                        "source_type": "imported",
                        "source_id": str(file_path),
                        "mood": mental_status.get("mood", ""),
                        "mood_intensity": mental_status.get("mood_intensity"),
                        "emotions": mental_status.get("emotions", {}),
                        "energy_level": mental_status.get("energy_level"),
                        "sleep_quality": mental_status.get("sleep_quality"),
                        "social_drive": mental_status.get("social_drive"),
                        "focus_level": mental_status.get("focus_level"),
                        "triggers": mental_status.get("triggers", ""),
                        "coping": mental_status.get("coping", ""),
                        "notes": mental_status.get("notes", ""),
                    }
                else:
                    status_record = None

                # Extract memories
                raw_memories = result.get("memories", [])
                valid_memories = [
                    m for m in raw_memories
                    if isinstance(m, dict) and m.get("category") and m.get("content")
                ]

                record_ids: list[str] = []
                memory_ids: list[str] = []

                if not dry_run:
                    session_id = f"{DIARY_SOURCE_SESSION_PREFIX}{file_path.name}"
                    if status_record:
                        rid = self.store.add_mental_status_record(status_record)
                        record_ids.append(rid)
                    for mem in valid_memories:
                        mid = self.store.add_memory(session_id, mem)
                        memory_ids.append(mid)
                else:
                    if status_record:
                        preview = {k: v for k, v in status_record.items() if v not in (None, "", {})}
                        LOGGER.info("  [dry-run] mental_status:\n%s", json.dumps(preview, ensure_ascii=False, indent=4))
                    for mem in valid_memories:
                        LOGGER.info(
                            "  [dry-run] memory: [%s] %s",
                            mem.get("category"),
                            mem.get("content", "")[:100],
                        )

                total_records += 1 if status_record else 0
                total_memories += len(valid_memories)

                if not dry_run:
                    self._upsert_source(file_path, file_hash, record_ids, memory_ids, record_date)

                imported_count += 1
                if delay_between_calls > 0 and idx < len(files):
                    time.sleep(delay_between_calls)

            except Exception:
                LOGGER.exception("failed to import diary file: %s", file_path)
                error_count += 1

        LOGGER.info(
            "diary import done: imported=%d skipped=%d errors=%d "
            "records=%d memories=%d total=%d",
            imported_count,
            skipped_count,
            error_count,
            total_records,
            total_memories,
            len(files),
        )
        return {
            "imported": imported_count,
            "skipped": skipped_count,
            "errors": error_count,
            "records_created": total_records,
            "memories_created": total_memories,
            "total": len(files),
        }


def run_import(
    store_path: str | None = None,
    dry_run: bool = False,
    delay: float = 1.0,
    limit: int | None = None,
) -> dict[str, Any]:
    from app.config import get_settings
    from app.llm.deepseek import DeepSeekClient
    settings = get_settings()
    if not settings.deepseek_api_key:
        raise SystemExit("缺少 DEEPSEEK_API_KEY，无法调用大模型分析日记。")
    db_path = store_path or settings.app_db_path
    store = Store(db_path)
    llm = DeepSeekClient(
        api_key=settings.deepseek_api_key,
        model=settings.deepseek_model,
        base_url=settings.deepseek_base_url,
        timeout=settings.deepseek_timeout,
        thinking="disabled",
        stream=False,
    )
    importer = DiaryImporter(store, llm=llm)
    return importer.import_diaries(dry_run=dry_run, delay_between_calls=delay, limit=limit)


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description="Import personal diary into memories and mental status records via LLM")
    parser.add_argument("--db", default=None, help="Database path")
    parser.add_argument("--dry-run", action="store_true", help="Preview without writing")
    parser.add_argument("--delay", type=float, default=1.0, help="Seconds between API calls (default: 1.0)")
    parser.add_argument("--limit", type=int, default=None, help="Only process first N files")
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    result = run_import(store_path=args.db, dry_run=args.dry_run, delay=args.delay, limit=args.limit)
    print(json.dumps(result, ensure_ascii=False, indent=2))
