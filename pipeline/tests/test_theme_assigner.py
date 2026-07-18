import json
from pathlib import Path
from unittest.mock import MagicMock

import pytest

from src.theme_assigner import (
    apply_rule,
    assign_theme_for_chapter,
    build_assignment_prompt,
    parse_assignment_response,
    should_skip_chapter,
    unique_chapters_from_manifest,
    validate_assignment,
    write_themes_atomic,
)
from src.theme_resolver import ThemeAssignment


def test_unique_chapters_from_manifest_returns_one_entry_per_book_chapter():
    manifest = {
        "groups": [
            {"book": "John", "chapter": 3, "start_verse": 16, "end_verse": 16},
            {"book": "John", "chapter": 3, "start_verse": 17, "end_verse": 20},
            {"book": "John", "chapter": 4, "start_verse": 1, "end_verse": 5},
        ]
    }

    chapters = unique_chapters_from_manifest(manifest)

    assert chapters == [("John", 3), ("John", 4)]


def test_apply_rule_returns_wisdom_lyrical_for_psalms():
    assignment = apply_rule("Psalms", 23, "The LORD is my shepherd")

    assert assignment is not None
    assert assignment.theme_id == "wisdom_lyrical"
    assert assignment.style == "clipart"


def test_apply_rule_returns_apocalyptic_dramatic_for_revelation():
    assignment = apply_rule("Revelation", 6, "I watched as the Lamb opened the first seal")

    assert assignment is not None
    assert assignment.theme_id == "apocalyptic_dramatic"
    assert assignment.style == "realistic"


def test_apply_rule_returns_creation_cosmic_for_genesis_one_with_creation_language():
    text = "In the beginning God created the heavens and the earth."
    assignment = apply_rule("Genesis", 1, text)

    assert assignment is not None
    assert assignment.theme_id == "creation_cosmic"


def test_apply_rule_returns_none_for_ambiguous_chapter():
    assignment = apply_rule("John", 11, "Now a man named Lazarus was sick.")

    assert assignment is None


def test_apply_rule_returns_none_when_text_says_crossed_the_jordan():
    assignment = apply_rule("Joshua", 3, "The people crossed the Jordan across from Jericho.")

    assert assignment is None


def test_apply_rule_returns_none_when_text_says_deserted():
    assignment = apply_rule("Ruth", 1, "The town felt deserted after the famine.")

    assert assignment is None


def test_apply_rule_returns_passion_somber_when_text_mentions_the_cross():
    assignment = apply_rule("Mark", 15, "They led Him out to be crucified near the cross.")

    assert assignment is not None
    assert assignment.theme_id == "passion_somber"


def test_apply_rule_returns_none_for_epistle_chapter_so_gemini_judges_it():
    assignment = apply_rule("Romans", 8, "There is now no condemnation for those in Christ.")

    assert assignment is None


def test_parse_assignment_response_returns_theme_assignment_from_json():
    assignment = parse_assignment_response(
        '{"theme_id": "gospel_light", "style": "realistic", "rationale": "Nicodemus encounter"}'
    )

    assert assignment.theme_id == "gospel_light"
    assert assignment.style == "realistic"
    assert assignment.rationale == "Nicodemus encounter"


def test_parse_assignment_response_handles_markdown_fenced_json():
    assignment = parse_assignment_response(
        '```json\n{"theme_id": "gospel_light", "style": "realistic", "rationale": "warm"}\n```'
    )

    assert assignment.theme_id == "gospel_light"
    assert assignment.style == "realistic"


def test_parse_assignment_response_defaults_style_to_empty_when_missing():
    assignment = parse_assignment_response('{"theme_id": "gospel_light"}')

    assert assignment.theme_id == "gospel_light"
    assert assignment.style == ""


def test_parse_assignment_response_raises_value_error_when_theme_id_missing():
    with pytest.raises(ValueError, match="theme_id"):
        parse_assignment_response('{"style": "realistic"}')


def test_build_assignment_prompt_lists_theme_catalog():
    registry = {
        "themes": {
            "gospel_light": {"description": "warm gospel", "default_style": "realistic"},
        }
    }
    prompt = build_assignment_prompt(
        book="John",
        chapter=3,
        chapter_text="For God so loved the world",
        registry=registry,
    )

    assert "John" in prompt
    assert "Chapter: 3" in prompt
    assert "gospel_light" in prompt
    assert "For God so loved the world" in prompt


def test_assign_theme_for_chapter_uses_rule_without_calling_gemini():
    registry_path = Path(__file__).resolve().parent.parent / "prompts" / "theme_registry.json"
    registry = json.loads(registry_path.read_text(encoding="utf-8"))
    gemini = MagicMock()

    assignment, source = assign_theme_for_chapter(
        book="Psalms",
        chapter=1,
        chapter_text="Blessed is the man",
        registry=registry,
        gemini_generate=gemini,
    )

    assert assignment.theme_id == "wisdom_lyrical"
    assert source == "rules"
    gemini.assert_not_called()


def test_assign_theme_for_chapter_fills_default_style_when_gemini_omits_style():
    registry = {
        "themes": {
            "gospel_light": {"description": "warm", "default_style": "realistic"},
        },
        "styles": {"realistic": "meta_prompt_realistic.txt"},
        "default_theme_id": "gospel_light",
    }

    assignment, source = assign_theme_for_chapter(
        book="John",
        chapter=11,
        chapter_text="Now a man named Lazarus was sick.",
        registry=registry,
        gemini_generate=lambda prompt: '{"theme_id": "gospel_light"}',
    )

    assert assignment.style == "realistic"
    assert source == "gemini"


def test_should_skip_chapter_returns_true_when_wildcard_override_covers_book(tmp_path: Path):
    overrides_path = tmp_path / "overrides.json"
    overrides_path.write_text(
        json.dumps({"Psalms": {"*": {"theme_id": "wisdom_lyrical", "style": "clipart"}}}),
        encoding="utf-8",
    )

    skipped = should_skip_chapter(
        "Psalms",
        23,
        themes_path=tmp_path / "missing.json",
        overrides_path=overrides_path,
        force=False,
    )

    assert skipped is True


def test_should_skip_chapter_returns_false_when_force_is_set(tmp_path: Path):
    overrides_path = tmp_path / "overrides.json"
    overrides_path.write_text(
        json.dumps({"Psalms": {"*": {"theme_id": "wisdom_lyrical", "style": "clipart"}}}),
        encoding="utf-8",
    )

    skipped = should_skip_chapter(
        "Psalms",
        23,
        themes_path=tmp_path / "missing.json",
        overrides_path=overrides_path,
        force=True,
    )

    assert skipped is False


def test_validate_assignment_raises_when_style_unknown():
    registry = {
        "themes": {"gospel_light": {"description": "warm", "default_style": "realistic"}},
        "styles": {"realistic": "meta_prompt_realistic.txt"},
    }

    with pytest.raises(ValueError, match="watercolor"):
        validate_assignment(
            ThemeAssignment(theme_id="gospel_light", style="watercolor"),
            registry,
        )


def test_write_themes_atomic_merges_book_chapter_entries(tmp_path: Path):
    themes_path = tmp_path / "themes.json"
    themes_path.write_text(
        json.dumps({"John": {"1": {"theme_id": "gospel_light", "style": "realistic"}}}),
        encoding="utf-8",
    )

    write_themes_atomic(
        themes_path,
        {
            "John": {
                "3": {
                    "theme_id": "gospel_light",
                    "style": "realistic",
                    "rationale": "famous verse",
                }
            }
        },
    )

    payload = json.loads(themes_path.read_text(encoding="utf-8"))
    assert payload["John"]["1"]["theme_id"] == "gospel_light"
    assert payload["John"]["3"]["rationale"] == "famous verse"
