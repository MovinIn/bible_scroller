from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path
from typing import Any


@dataclass(frozen=True)
class ThemeAssignment:
    theme_id: str
    style: str
    rationale: str = ""


@dataclass(frozen=True)
class ResolvedTheme:
    assignment: ThemeAssignment
    meta_prompt_path: Path
    theme_guidance: str
    source: str


def load_registry(registry_path: Path) -> dict[str, Any]:
    return json.loads(registry_path.read_text(encoding="utf-8"))


def load_themes(themes_path: Path) -> dict[str, Any]:
    if not themes_path.exists():
        return {}
    return json.loads(themes_path.read_text(encoding="utf-8"))


def load_overrides(overrides_path: Path) -> dict[str, Any]:
    if not overrides_path.exists():
        return {}
    return json.loads(overrides_path.read_text(encoding="utf-8"))


def _lookup_book_entry(entries: dict[str, Any], chapter: int) -> dict[str, Any] | None:
    chapter_key = str(chapter)
    if chapter_key in entries:
        return entries[chapter_key]
    if "*" in entries:
        return entries["*"]
    return None


def _assignment_from_payload(payload: dict[str, Any]) -> ThemeAssignment:
    return ThemeAssignment(
        theme_id=payload["theme_id"],
        style=payload.get("style", ""),
        rationale=payload.get("rationale", ""),
    )


def _find_override(
    overrides: dict[str, Any],
    book: str,
    chapter: int,
) -> ThemeAssignment | None:
    for book_key, entries in overrides.items():
        if book_key.casefold() != book.casefold():
            continue
        payload = _lookup_book_entry(entries, chapter)
        if payload is not None:
            return _assignment_from_payload(payload)
    return None


def _find_cached(
    themes: dict[str, Any],
    book: str,
    chapter: int,
) -> ThemeAssignment | None:
    for book_key, entries in themes.items():
        if book_key.casefold() != book.casefold():
            continue
        payload = entries.get(str(chapter))
        if payload is not None:
            return _assignment_from_payload(payload)
    return None


def _default_assignment(registry: dict[str, Any]) -> ThemeAssignment:
    theme_id = registry.get("default_theme_id", "gospel_light")
    theme = registry["themes"][theme_id]
    return ThemeAssignment(
        theme_id=theme_id,
        style=theme["default_style"],
    )


def _read_mood_guidance(prompts_dir: Path, mood_file: str) -> str:
    path = prompts_dir / mood_file
    return path.read_text(encoding="utf-8").strip()


def _meta_prompt_path(prompts_dir: Path, registry: dict[str, Any], style: str) -> Path:
    styles = registry.get("styles", {})
    if style not in styles:
        raise ValueError(f"Unknown style: {style!r}")
    return prompts_dir / styles[style]


def resolve_theme(
    book: str,
    chapter: int,
    *,
    registry_path: Path,
    overrides_path: Path,
    themes_path: Path,
    prompts_dir: Path,
    assignment: ThemeAssignment | None = None,
) -> ResolvedTheme:
    registry = load_registry(registry_path)
    overrides = load_overrides(overrides_path)
    themes = load_themes(themes_path)

    source = "default"
    if assignment is not None:
        resolved_assignment = assignment
        source = "explicit"
    else:
        override = _find_override(overrides, book, chapter)
        if override is not None:
            resolved_assignment = override
            source = "override"
        else:
            cached = _find_cached(themes, book, chapter)
            if cached is not None:
                resolved_assignment = cached
                source = "cached"
            else:
                resolved_assignment = _default_assignment(registry)
                source = "default"

    theme_entry = registry["themes"].get(resolved_assignment.theme_id)
    if theme_entry is None:
        raise ValueError(f"Unknown theme_id: {resolved_assignment.theme_id!r}")

    style = resolved_assignment.style or theme_entry["default_style"]
    mood_file = theme_entry["mood_file"]
    theme_guidance = _read_mood_guidance(prompts_dir, mood_file)
    meta_prompt_path = _meta_prompt_path(prompts_dir, registry, style)

    return ResolvedTheme(
        assignment=ThemeAssignment(
            theme_id=resolved_assignment.theme_id,
            style=style,
            rationale=resolved_assignment.rationale,
        ),
        meta_prompt_path=meta_prompt_path,
        theme_guidance=theme_guidance,
        source=source,
    )


def resolve_generation_theme(
    book: str,
    chapter: int,
    *,
    themes_path: Path | None,
    fallback_meta_prompt: Path,
    registry_path: Path,
    overrides_path: Path,
    prompts_dir: Path,
) -> tuple[Path, str, ResolvedTheme | None]:
    if themes_path is not None and themes_path.exists():
        resolved = resolve_theme(
            book,
            chapter,
            registry_path=registry_path,
            overrides_path=overrides_path,
            themes_path=themes_path,
            prompts_dir=prompts_dir,
        )
        # Only apply a theme that was explicitly assigned or overridden;
        # unassigned chapters use the plain fallback meta-prompt so a partial
        # themes.json does not stamp the default mood over everything else.
        if resolved.source != "default":
            return resolved.meta_prompt_path, resolved.theme_guidance, resolved
    return fallback_meta_prompt, "", None
