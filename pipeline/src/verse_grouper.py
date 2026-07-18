from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from src.bible_client import list_verse_numbers
from src.reference import VerseReference


@dataclass(frozen=True)
class GroupingConfig:
    min_group_size: int = 4
    max_group_size: int = 5

    def __post_init__(self) -> None:
        if self.min_group_size < 1:
            raise ValueError("min_group_size must be at least 1")
        if self.max_group_size < self.min_group_size:
            raise ValueError("max_group_size must be >= min_group_size")


def validate_coverage(
    groups: list[VerseReference],
    chapter_payload: dict[str, Any],
) -> None:
    expected = set(list_verse_numbers(chapter_payload))
    covered: set[int] = set()
    for group in groups:
        for verse_number in range(group.start_verse, group.end_verse + 1):
            if verse_number in covered:
                raise ValueError(
                    f"Verse {verse_number} appears in multiple groups "
                    f"({group.book} {group.chapter})"
                )
            covered.add(verse_number)
    if covered != expected:
        missing = sorted(expected - covered)
        extra = sorted(covered - expected)
        raise ValueError(
            f"Chapter coverage mismatch: missing {missing}, extra {extra}"
        )


def _append_contiguous_groups(
    groups: list[VerseReference],
    verse_numbers: list[int],
    *,
    book: str,
    chapter: int,
) -> None:
    if not verse_numbers:
        return
    start_idx = 0
    for index in range(1, len(verse_numbers)):
        if verse_numbers[index] != verse_numbers[index - 1] + 1:
            groups.append(
                VerseReference(
                    book=book,
                    chapter=chapter,
                    start_verse=verse_numbers[start_idx],
                    end_verse=verse_numbers[index - 1],
                )
            )
            start_idx = index
    groups.append(
        VerseReference(
            book=book,
            chapter=chapter,
            start_verse=verse_numbers[start_idx],
            end_verse=verse_numbers[-1],
        )
    )


def group_chapter(
    chapter_payload: dict[str, Any],
    *,
    book: str,
    chapter: int,
    config: GroupingConfig | None = None,
    min_group_size: int | None = None,
    max_group_size: int | None = None,
) -> list[VerseReference]:
    if config is None:
        config = GroupingConfig(
            min_group_size=min_group_size if min_group_size is not None else 4,
            max_group_size=max_group_size if max_group_size is not None else 5,
        )
    elif min_group_size is not None or max_group_size is not None:
        config = GroupingConfig(
            min_group_size=min_group_size if min_group_size is not None else config.min_group_size,
            max_group_size=max_group_size if max_group_size is not None else config.max_group_size,
        )

    content = chapter_payload.get("chapter", {}).get("content", [])
    groups: list[VerseReference] = []
    current: list[int] = []

    def flush() -> None:
        nonlocal current
        if not current:
            return
        _append_contiguous_groups(groups, current, book=book, chapter=chapter)
        current = []

    for block in content:
        block_type = block.get("type")

        if block_type == "heading":
            flush()
            continue

        if block_type == "verse":
            number = block.get("number")
            if number is None:
                continue
            verse_number = int(number)
            if current and verse_number != current[-1] + 1:
                flush()
            current.append(verse_number)
            while len(current) > config.max_group_size:
                chunk = current[: config.max_group_size]
                current = current[config.max_group_size :]
                _append_contiguous_groups(groups, chunk, book=book, chapter=chapter)
            continue

        if block_type == "line_break":
            if len(current) >= config.min_group_size:
                flush()
            continue

    flush()
    return groups
