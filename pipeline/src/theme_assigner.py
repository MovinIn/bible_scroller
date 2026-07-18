from __future__ import annotations

import json
import os
import re
from pathlib import Path
from typing import Any, Callable

from src.theme_resolver import ThemeAssignment, load_overrides, load_registry, load_themes


_JSON_BLOCK_PATTERN = re.compile(r"\{[^{}]*\}")

_PARABLE_CHAPTERS: dict[str, frozenset[int]] = {
    "Matthew": frozenset({13, 18, 20, 21, 22, 25}),
    "Mark": frozenset({4, 12}),
    "Luke": frozenset({8, 10, 12, 13, 14, 15, 16, 18, 19}),
}

# Word-boundary patterns so e.g. "crossed"/"across" or "deserted" do not
# trigger a theme.
_TEMPLE_PATTERN = re.compile(r"\b(temple|sanctuary)\b")
_WILDERNESS_PATTERN = re.compile(r"\b(wilderness|desert)\b")
_RESURRECTION_PATTERN = re.compile(r"\bresurrection\b|raised from the dead")
_PASSION_PATTERN = re.compile(r"\b(cross|crucify|crucified|golgotha)\b")


def unique_chapters_from_manifest(manifest: dict[str, Any]) -> list[tuple[str, int]]:
    seen: set[tuple[str, int]] = set()
    chapters: list[tuple[str, int]] = []
    for entry in manifest.get("groups", []):
        key = (entry["book"], int(entry["chapter"]))
        if key not in seen:
            seen.add(key)
            chapters.append(key)
    return chapters


def apply_rule(book: str, chapter: int, chapter_text: str) -> ThemeAssignment | None:
    folded_book = book.casefold()

    if folded_book in {"psalms", "psalm", "song of solomon"}:
        return ThemeAssignment(
            theme_id="wisdom_lyrical",
            style="clipart",
            rationale="Poetic/wisdom book default rule",
        )

    if folded_book == "revelation":
        return ThemeAssignment(
            theme_id="apocalyptic_dramatic",
            style="realistic",
            rationale="Apocalyptic book default rule",
        )

    if book == "Genesis" and chapter == 1:
        lowered = chapter_text.casefold()
        if "created" in lowered or "beginning" in lowered:
            return ThemeAssignment(
                theme_id="creation_cosmic",
                style="realistic",
                rationale="Creation account keyword rule",
            )

    if book == "Genesis" and chapter == 2:
        return ThemeAssignment(
            theme_id="garden_peace",
            style="clipart",
            rationale="Eden/garden chapter rule",
        )

    if book == "Exodus" and chapter == 14:
        return ThemeAssignment(
            theme_id="exodus_deliverance",
            style="realistic",
            rationale="Red Sea crossing chapter rule",
        )

    parable_chapters = _PARABLE_CHAPTERS.get(book)
    if parable_chapters is not None and chapter in parable_chapters:
        return ThemeAssignment(
            theme_id="parable_storybook",
            style="clipart",
            rationale="Parable-heavy chapter rule",
        )

    lowered = chapter_text.casefold()
    if _TEMPLE_PATTERN.search(lowered):
        return ThemeAssignment(
            theme_id="temple_worship",
            style="realistic",
            rationale="Temple keyword rule",
        )

    if _WILDERNESS_PATTERN.search(lowered):
        return ThemeAssignment(
            theme_id="wilderness_journey",
            style="realistic",
            rationale="Wilderness keyword rule",
        )

    if _RESURRECTION_PATTERN.search(lowered):
        return ThemeAssignment(
            theme_id="resurrection_dawn",
            style="realistic",
            rationale="Resurrection keyword rule",
        )

    if _PASSION_PATTERN.search(lowered):
        return ThemeAssignment(
            theme_id="passion_somber",
            style="realistic",
            rationale="Passion keyword rule",
        )

    return None


def build_assignment_prompt(
    *,
    book: str,
    chapter: int,
    chapter_text: str,
    registry: dict[str, Any],
    max_chars: int = 12000,
) -> str:
    catalog_lines: list[str] = []
    for theme_id, theme in registry["themes"].items():
        catalog_lines.append(
            f"- {theme_id}: {theme['description']} (default style: {theme['default_style']})"
        )
    catalog = "\n".join(catalog_lines)
    truncated = chapter_text
    if len(chapter_text) > max_chars:
        truncated = chapter_text[:max_chars] + "\n[truncated]"

    return (
        "You are assigning a visual theme to a Bible chapter for a scroller app.\n"
        "Pick the single best theme_id and style from the catalog for this chapter's feel.\n"
        "Valid styles: realistic, clipart.\n\n"
        f"Book: {book}\n"
        f"Chapter: {chapter}\n\n"
        "Theme catalog:\n"
        f"{catalog}\n\n"
        "Chapter text (BSB):\n"
        f"{truncated}\n\n"
        "Respond with ONLY valid JSON, no markdown:\n"
        '{"theme_id": "...", "style": "realistic|clipart", "rationale": "one sentence"}'
    )


def parse_assignment_response(text: str) -> ThemeAssignment:
    stripped = text.strip()
    if stripped.startswith("```"):
        stripped = stripped.strip("`")
        if stripped.lower().startswith("json"):
            stripped = stripped[4:].strip()

    try:
        payload = json.loads(stripped)
    except json.JSONDecodeError:
        match = _JSON_BLOCK_PATTERN.search(stripped)
        if match is None:
            raise ValueError(f"Could not parse theme assignment JSON: {text!r}") from None
        payload = json.loads(match.group(0))

    theme_id = payload.get("theme_id")
    if not theme_id:
        raise ValueError(f"Theme assignment response is missing theme_id: {text!r}")

    return ThemeAssignment(
        theme_id=theme_id,
        style=payload.get("style", ""),
        rationale=payload.get("rationale", ""),
    )


def assign_theme_for_chapter(
    *,
    book: str,
    chapter: int,
    chapter_text: str,
    registry: dict[str, Any],
    gemini_generate: Callable[[str], str] | None = None,
) -> tuple[ThemeAssignment, str]:
    ruled = apply_rule(book, chapter, chapter_text)
    if ruled is not None:
        return ruled, "rules"

    if gemini_generate is None:
        default_id = registry.get("default_theme_id", "gospel_light")
        default_theme = registry["themes"][default_id]
        return (
            ThemeAssignment(
                theme_id=default_id,
                style=default_theme["default_style"],
                rationale="No rule matched; default theme",
            ),
            "default",
        )

    prompt = build_assignment_prompt(
        book=book,
        chapter=chapter,
        chapter_text=chapter_text,
        registry=registry,
    )
    response = gemini_generate(prompt)
    assignment = parse_assignment_response(response)
    if not assignment.style:
        theme = registry["themes"].get(assignment.theme_id)
        if theme is not None:
            assignment = ThemeAssignment(
                theme_id=assignment.theme_id,
                style=theme["default_style"],
                rationale=assignment.rationale,
            )
    return assignment, "gemini"


def assignment_to_payload(assignment: ThemeAssignment) -> dict[str, str]:
    payload = {
        "theme_id": assignment.theme_id,
        "style": assignment.style,
    }
    if assignment.rationale:
        payload["rationale"] = assignment.rationale
    return payload


def write_themes_atomic(path: Path, updates: dict[str, dict[str, dict[str, str]]]) -> None:
    existing = load_themes(path)
    for book, chapters in updates.items():
        book_entry = existing.setdefault(book, {})
        for chapter_key, payload in chapters.items():
            book_entry[chapter_key] = payload
    path.parent.mkdir(parents=True, exist_ok=True)
    temp_path = path.with_suffix(f"{path.suffix}.tmp")
    temp_path.write_text(json.dumps(existing, indent=2), encoding="utf-8")
    os.replace(temp_path, path)


def should_skip_chapter(
    book: str,
    chapter: int,
    *,
    themes_path: Path,
    overrides_path: Path,
    force: bool,
) -> bool:
    if force:
        return False
    overrides = load_overrides(overrides_path)
    if _find_override_book(overrides, book, chapter) is not None:
        return True
    themes = load_themes(themes_path)
    for book_key, entries in themes.items():
        if book_key.casefold() == book.casefold() and str(chapter) in entries:
            return True
    return False


def _find_override_book(overrides: dict[str, Any], book: str, chapter: int) -> dict[str, Any] | None:
    for book_key, entries in overrides.items():
        if book_key.casefold() != book.casefold():
            continue
        chapter_key = str(chapter)
        if chapter_key in entries or "*" in entries:
            return entries.get(chapter_key) or entries.get("*")
    return None


def validate_assignment(assignment: ThemeAssignment, registry: dict[str, Any]) -> None:
    if assignment.theme_id not in registry["themes"]:
        raise ValueError(f"Unknown theme_id from assignment: {assignment.theme_id!r}")
    if assignment.style not in registry.get("styles", {}):
        raise ValueError(f"Unknown style from assignment: {assignment.style!r}")
