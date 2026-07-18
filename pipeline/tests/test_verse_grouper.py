import json
from pathlib import Path

import pytest

from src.reference import VerseReference, parse_reference
from src.verse_grouper import GroupingConfig, group_chapter, validate_coverage

FIXTURES = Path(__file__).resolve().parent / "fixtures"


@pytest.fixture
def john_3_chapter() -> dict:
    return json.loads((FIXTURES / "john_3_chapter.json").read_text(encoding="utf-8"))


def _refs(groups: list[VerseReference]) -> list[tuple[int, int]]:
    return [(g.start_verse, g.end_verse) for g in groups]


def test_splits_at_heading_when_section_changes(john_3_chapter):
    groups = group_chapter(john_3_chapter, book="John", chapter=3)
    ranges = _refs(groups)

    assert (19, 21) in ranges
    assert (22, 26) in ranges
    heading_split_index = ranges.index((19, 21))
    assert ranges[heading_split_index + 1] == (22, 26)


def test_splits_at_line_break_when_group_reaches_min_size(john_3_chapter):
    groups = group_chapter(john_3_chapter, book="John", chapter=3)

    assert _refs(groups)[0] == (1, 4)


def test_caps_group_at_max_size_when_no_soft_breaks(john_3_chapter):
    groups = group_chapter(john_3_chapter, book="John", chapter=3)
    ranges = _refs(groups)

    assert (5, 8) in ranges
    assert (9, 13) in ranges
    assert all(end - start + 1 <= 5 for start, end in ranges)


def test_flushes_remainder_under_min_at_chapter_end(john_3_chapter):
    groups = group_chapter(john_3_chapter, book="John", chapter=3)

    assert groups[-1] == VerseReference(
        book="John", chapter=3, start_verse=35, end_verse=36
    )
    assert groups[-1].end_verse - groups[-1].start_verse + 1 == 2


def test_returns_reference_strings_compatible_with_parse_reference(john_3_chapter):
    groups = group_chapter(john_3_chapter, book="John", chapter=3)

    for group in groups:
        reference = f"{group.book} {group.chapter}:{group.start_verse}"
        if group.end_verse != group.start_verse:
            reference += f"-{group.end_verse}"
        parsed = parse_reference(reference)
        assert parsed == group


def test_groups_all_verses_in_chapter_when_structure_aware(john_3_chapter):
    groups = group_chapter(john_3_chapter, book="John", chapter=3)

    covered: list[int] = []
    for group in groups:
        covered.extend(range(group.start_verse, group.end_verse + 1))

    assert covered == list(range(1, 37))


def test_falls_back_to_mechanical_chunks_when_chapter_has_no_structure_markers():
    payload = {
        "chapter": {
            "content": [{"type": "verse", "number": n, "content": [f"Verse {n}."]} for n in range(1, 13)]
        }
    }
    groups = group_chapter(payload, book="Psalms", chapter=119, max_group_size=5)

    assert _refs(groups) == [(1, 5), (6, 10), (11, 12)]


def test_respects_custom_min_and_max_sizes():
    payload = {
        "chapter": {
            "content": [{"type": "verse", "number": n, "content": [f"Verse {n}."]} for n in range(1, 8)]
        }
    }
    config = GroupingConfig(min_group_size=2, max_group_size=3)
    groups = group_chapter(payload, book="John", chapter=1, config=config)

    assert _refs(groups) == [(1, 3), (4, 6), (7, 7)]


def test_grouping_config_rejects_invalid_bounds():
    with pytest.raises(ValueError, match="max_group_size must be >= min_group_size"):
        GroupingConfig(min_group_size=5, max_group_size=4)


def test_splits_groups_at_verse_number_gaps():
    payload = {
        "chapter": {
            "content": [
                {"type": "verse", "number": 1, "content": ["A"]},
                {"type": "verse", "number": 2, "content": ["B"]},
                {"type": "verse", "number": 4, "content": ["C"]},
                {"type": "verse", "number": 5, "content": ["D"]},
            ]
        }
    }
    groups = group_chapter(payload, book="John", chapter=1)

    assert _refs(groups) == [(1, 2), (4, 5)]


def test_validate_coverage_raises_when_groups_overlap():
    payload = {
        "chapter": {
            "content": [{"type": "verse", "number": n, "content": [f"V{n}"]} for n in (1, 2, 3)],
        }
    }
    groups = [
        VerseReference(book="John", chapter=1, start_verse=1, end_verse=2),
        VerseReference(book="John", chapter=1, start_verse=2, end_verse=3),
    ]

    with pytest.raises(ValueError, match="appears in multiple groups"):
        validate_coverage(groups, payload)
