from __future__ import annotations

import json
import os
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from src.config import BIBLE_TRANSLATION
from src.reference import VerseReference


def format_reference(reference: VerseReference) -> str:
    if reference.start_verse == reference.end_verse:
        return f"{reference.book} {reference.chapter}:{reference.start_verse}"
    return f"{reference.book} {reference.chapter}:{reference.start_verse}-{reference.end_verse}"


def group_to_manifest_entry(group_id: int, reference: VerseReference) -> dict[str, Any]:
    verse_count = reference.end_verse - reference.start_verse + 1
    return {
        "id": group_id,
        "reference": format_reference(reference),
        "book": reference.book,
        "chapter": reference.chapter,
        "start_verse": reference.start_verse,
        "end_verse": reference.end_verse,
        "verse_count": verse_count,
        "slug": reference.slug(),
    }


def build_manifest(
    groups: list[VerseReference],
    *,
    min_size: int,
    max_size: int,
    books_processed: int,
    canonical_verse_total: int | None = None,
) -> dict[str, Any]:
    entries = [group_to_manifest_entry(index + 1, group) for index, group in enumerate(groups)]
    total_verses = sum(entry["verse_count"] for entry in entries)
    stats: dict[str, Any] = {
        "total_groups": len(entries),
        "total_verses": total_verses,
        "books": books_processed,
    }
    if canonical_verse_total is not None:
        stats["canonical_verse_total"] = canonical_verse_total
        stats["verse_count_delta"] = total_verses - canonical_verse_total
    return {
        "translation": BIBLE_TRANSLATION,
        "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "grouping": {
            "min_size": min_size,
            "max_size": max_size,
            "strategy": "structure_aware",
        },
        "stats": stats,
        "groups": entries,
    }


def write_manifest_atomic(path: Path, manifest: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temp_path = path.with_suffix(f"{path.suffix}.tmp")
    temp_path.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    os.replace(temp_path, path)
