from __future__ import annotations

import json
from functools import lru_cache
from pathlib import Path
from typing import Any


# Process-local cache of chapter JSON file contents. Disk updates are not visible
# until clear_chapter_payload_cache() runs (called on app lifespan startup).
@lru_cache(maxsize=128)
def _read_chapter_file(cache_root_str: str, book_id: str, chapter: int) -> str | None:
    path = Path(cache_root_str) / book_id / f"{chapter}.json"
    if not path.is_file():
        return None
    return path.read_text(encoding="utf-8")


def load_chapter_payload(cache_root: Path, *, book_id: str, chapter: int) -> dict[str, Any] | None:
    raw = _read_chapter_file(str(cache_root), book_id, chapter)
    if raw is None:
        return None
    return json.loads(raw)


def clear_chapter_payload_cache() -> None:
    _read_chapter_file.cache_clear()


def extract_verse_range_text(
    payload: dict[str, Any],
    *,
    start_verse: int,
    end_verse: int,
) -> str:
    content = payload.get("chapter", {}).get("content", [])
    verses: dict[int, str] = {}

    for block in content:
        if not isinstance(block, dict) or block.get("type") != "verse":
            continue
        number = block.get("number")
        if number is None:
            continue
        verses[int(number)] = _flatten_verse_content(block.get("content", []))

    lines: list[str] = []
    for verse_number in range(start_verse, end_verse + 1):
        text = verses.get(verse_number)
        if text is None:
            continue
        lines.append(f"{verse_number} {text}")

    if not lines:
        raise ValueError(f"No verses found in range {start_verse}-{end_verse}")
    return "\n".join(lines)


def extract_chapter_audio_url(payload: dict[str, Any]) -> str | None:
    links = payload.get("thisChapterAudioLinks")
    if not isinstance(links, dict):
        return None
    for key in ("david", "hays", "souer"):
        value = links.get(key)
        if isinstance(value, str) and value.startswith("http"):
            return value
    for value in links.values():
        if isinstance(value, str) and value.startswith("http"):
            return value
    return None


def _flatten_verse_content(content: list[Any]) -> str:
    parts: list[str] = [item for item in content if isinstance(item, str)]
    if not parts:
        return ""

    result = parts[0]
    for part in parts[1:]:
        if (
            result
            and part
            and not result[-1].isspace()
            and part[0] not in ".,;:!?'\"-) "
            and result[-1].isalnum()
            and part[0].isalnum()
        ):
            result += " "
        result += part
    return result.strip()
