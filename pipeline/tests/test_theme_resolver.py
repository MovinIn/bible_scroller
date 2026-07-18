import json
from pathlib import Path

import pytest

from src.theme_resolver import (
    ThemeAssignment,
    load_overrides,
    load_registry,
    load_themes,
    resolve_generation_theme,
    resolve_theme,
)


def _write_registry(tmp_path: Path) -> Path:
    registry_path = tmp_path / "theme_registry.json"
    registry_path.write_text(
        json.dumps(
            {
                "themes": {
                    "gospel_light": {
                        "description": "warm gospel",
                        "default_style": "realistic",
                        "mood_file": "themes/gospel_light.txt",
                    },
                    "wisdom_lyrical": {
                        "description": "reflective psalms",
                        "default_style": "clipart",
                        "mood_file": "themes/wisdom_lyrical.txt",
                    },
                },
                "styles": {
                    "realistic": "meta_prompt_realistic.txt",
                    "clipart": "meta_prompt_clipart.txt",
                },
                "default_theme_id": "gospel_light",
            }
        ),
        encoding="utf-8",
    )
    prompts_dir = tmp_path
    (prompts_dir / "themes").mkdir()
    (prompts_dir / "themes" / "gospel_light.txt").write_text(
        "Gospel mood guidance.", encoding="utf-8"
    )
    (prompts_dir / "themes" / "wisdom_lyrical.txt").write_text(
        "Wisdom mood guidance.", encoding="utf-8"
    )
    (prompts_dir / "meta_prompt_realistic.txt").write_text(
        "Realistic shell {theme_guidance}", encoding="utf-8"
    )
    (prompts_dir / "meta_prompt_clipart.txt").write_text(
        "Clipart shell {theme_guidance}", encoding="utf-8"
    )
    return registry_path


def test_resolve_theme_uses_override_when_book_chapter_matches(tmp_path: Path):
    registry_path = _write_registry(tmp_path)
    overrides_path = tmp_path / "overrides.json"
    overrides_path.write_text(
        json.dumps(
            {
                "John": {
                    "3": {"theme_id": "wisdom_lyrical", "style": "clipart"},
                }
            }
        ),
        encoding="utf-8",
    )

    resolved = resolve_theme(
        "John",
        3,
        registry_path=registry_path,
        overrides_path=overrides_path,
        themes_path=tmp_path / "missing.json",
        prompts_dir=tmp_path,
    )

    assert resolved.assignment.theme_id == "wisdom_lyrical"
    assert resolved.assignment.style == "clipart"
    assert resolved.source == "override"
    assert resolved.theme_guidance == "Wisdom mood guidance."
    assert resolved.meta_prompt_path.name == "meta_prompt_clipart.txt"


def test_resolve_theme_uses_wildcard_override_when_chapter_specific_missing(tmp_path: Path):
    registry_path = _write_registry(tmp_path)
    overrides_path = tmp_path / "overrides.json"
    overrides_path.write_text(
        json.dumps(
            {
                "Psalms": {
                    "*": {"theme_id": "wisdom_lyrical", "style": "clipart"},
                }
            }
        ),
        encoding="utf-8",
    )

    resolved = resolve_theme(
        "Psalms",
        23,
        registry_path=registry_path,
        overrides_path=overrides_path,
        themes_path=tmp_path / "missing.json",
        prompts_dir=tmp_path,
    )

    assert resolved.assignment.theme_id == "wisdom_lyrical"
    assert resolved.source == "override"


def test_resolve_theme_uses_cached_themes_when_no_override(tmp_path: Path):
    registry_path = _write_registry(tmp_path)
    themes_path = tmp_path / "themes.json"
    themes_path.write_text(
        json.dumps(
            {
                "Genesis": {
                    "1": {
                        "theme_id": "gospel_light",
                        "style": "realistic",
                        "rationale": "creation",
                    }
                }
            }
        ),
        encoding="utf-8",
    )

    resolved = resolve_theme(
        "Genesis",
        1,
        registry_path=registry_path,
        overrides_path=tmp_path / "empty.json",
        themes_path=themes_path,
        prompts_dir=tmp_path,
    )

    assert resolved.assignment.theme_id == "gospel_light"
    assert resolved.assignment.rationale == "creation"
    assert resolved.source == "cached"
    assert resolved.theme_guidance == "Gospel mood guidance."


def test_resolve_theme_falls_back_to_default_theme_when_no_override_or_cache(tmp_path: Path):
    registry_path = _write_registry(tmp_path)

    resolved = resolve_theme(
        "Romans",
        8,
        registry_path=registry_path,
        overrides_path=tmp_path / "empty.json",
        themes_path=tmp_path / "missing.json",
        prompts_dir=tmp_path,
    )

    assert resolved.assignment.theme_id == "gospel_light"
    assert resolved.assignment.style == "realistic"
    assert resolved.source == "default"


def test_resolve_theme_uses_theme_default_style_when_override_omits_style(tmp_path: Path):
    registry_path = _write_registry(tmp_path)
    overrides_path = tmp_path / "overrides.json"
    overrides_path.write_text(
        json.dumps({"John": {"3": {"theme_id": "wisdom_lyrical"}}}),
        encoding="utf-8",
    )

    resolved = resolve_theme(
        "John",
        3,
        registry_path=registry_path,
        overrides_path=overrides_path,
        themes_path=tmp_path / "missing.json",
        prompts_dir=tmp_path,
    )

    assert resolved.assignment.style == "clipart"
    assert resolved.meta_prompt_path.name == "meta_prompt_clipart.txt"


def test_resolve_generation_theme_falls_back_when_chapter_not_assigned_in_existing_themes(
    tmp_path: Path,
):
    registry_path = _write_registry(tmp_path)
    themes_path = tmp_path / "themes.json"
    themes_path.write_text(
        json.dumps({"John": {"3": {"theme_id": "gospel_light", "style": "realistic"}}}),
        encoding="utf-8",
    )
    fallback = tmp_path / "meta_prompt_realistic.txt"

    meta_prompt_path, theme_guidance, resolved = resolve_generation_theme(
        "Genesis",
        1,
        themes_path=themes_path,
        fallback_meta_prompt=fallback,
        registry_path=registry_path,
        overrides_path=tmp_path / "empty.json",
        prompts_dir=tmp_path,
    )

    assert meta_prompt_path == fallback
    assert theme_guidance == ""
    assert resolved is None


def test_resolve_generation_theme_uses_fallback_when_themes_file_missing(tmp_path: Path):
    registry_path = _write_registry(tmp_path)
    fallback = tmp_path / "meta_prompt_realistic.txt"

    meta_prompt_path, theme_guidance, resolved = resolve_generation_theme(
        "John",
        3,
        themes_path=tmp_path / "missing.json",
        fallback_meta_prompt=fallback,
        registry_path=registry_path,
        overrides_path=tmp_path / "empty.json",
        prompts_dir=tmp_path,
    )

    assert meta_prompt_path == fallback
    assert theme_guidance == ""
    assert resolved is None


def test_load_overrides_returns_empty_dict_when_file_missing(tmp_path: Path):
    assert load_overrides(tmp_path / "missing.json") == {}


def test_load_themes_returns_empty_dict_when_file_missing(tmp_path: Path):
    assert load_themes(tmp_path / "missing.json") == {}


def test_load_registry_raises_when_theme_id_unknown(tmp_path: Path):
    registry_path = _write_registry(tmp_path)

    with pytest.raises(ValueError, match="unknown_theme"):
        resolve_theme(
            "John",
            1,
            registry_path=registry_path,
            overrides_path=tmp_path / "empty.json",
            themes_path=tmp_path / "themes.json",
            prompts_dir=tmp_path,
            assignment=ThemeAssignment(theme_id="unknown_theme", style="realistic"),
        )
