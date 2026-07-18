#!/usr/bin/env python3
"""Group all Bible chapters into scroll-sized verse bunches."""

from __future__ import annotations

import argparse
from pathlib import Path

from src.bible_client import BibleClient, BookInfo
from src.config import (
    CHAPTER_CACHE_DIR,
    DEFAULT_MANIFEST,
    DEFAULT_MAX_GROUP_SIZE,
    DEFAULT_MIN_GROUP_SIZE,
)
from src.manifest import build_manifest, write_manifest_atomic
from src.reference import VerseReference
from src.verse_grouper import GroupingConfig, group_chapter, validate_coverage


def _matches_book_filter(book: BookInfo, book_filter: str) -> bool:
    folded = book_filter.casefold()
    return book.name.casefold() == folded or book.common_name.casefold() == folded


def collect_groups(
    bible: BibleClient,
    *,
    book_filter: str | None,
    cache_dir: Path | None,
    use_cache: bool,
    config: GroupingConfig,
    output_path: Path | None = None,
    canonical_verse_total: int | None = None,
) -> tuple[list[VerseReference], int]:
    groups: list[VerseReference] = []
    books = bible.list_books()
    if book_filter is not None:
        books = [book for book in books if _matches_book_filter(book, book_filter)]
        if not books:
            raise ValueError(f"Unknown book: {book_filter!r}")

    books_processed = 0
    for book in books:
        for chapter_num in range(1, book.number_of_chapters + 1):
            chapter_payload = bible.fetch_chapter_cached(
                book.id,
                chapter_num,
                cache_dir=cache_dir,
                use_cache=use_cache,
            )
            chapter_groups = group_chapter(
                chapter_payload,
                book=book.name,
                chapter=chapter_num,
                config=config,
            )
            validate_coverage(chapter_groups, chapter_payload)
            groups.extend(chapter_groups)
            print(
                f"{book.name} {chapter_num}/{book.number_of_chapters} "
                f"-> {len(chapter_groups)} groups ({len(groups)} total)",
                flush=True,
            )

        books_processed += 1
        if output_path is not None:
            manifest = build_manifest(
                groups,
                min_size=config.min_group_size,
                max_size=config.max_group_size,
                books_processed=books_processed,
                canonical_verse_total=canonical_verse_total,
            )
            write_manifest_atomic(output_path, manifest)

    return groups, books_processed


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Group Bible verses into scroll-sized bunches (~4-5 verses).",
    )
    parser.add_argument(
        "--min-size",
        type=int,
        default=DEFAULT_MIN_GROUP_SIZE,
        help="Minimum verses before splitting at a line break (default: 4)",
    )
    parser.add_argument(
        "--max-size",
        type=int,
        default=DEFAULT_MAX_GROUP_SIZE,
        help="Maximum verses per group (default: 5)",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=DEFAULT_MANIFEST,
        help="Path for manifest JSON output",
    )
    parser.add_argument(
        "--cache-dir",
        type=Path,
        default=CHAPTER_CACHE_DIR,
        help="Directory for cached chapter JSON",
    )
    parser.add_argument(
        "--book",
        help='Process only one book, e.g. "John"',
    )
    parser.add_argument(
        "--no-cache",
        action="store_true",
        help="Always fetch chapters from the API (do not read or write cache)",
    )
    args = parser.parse_args(argv)

    config = GroupingConfig(
        min_group_size=args.min_size,
        max_group_size=args.max_size,
    )
    use_cache = not args.no_cache
    cache_dir = None if args.no_cache else args.cache_dir

    bible = BibleClient()
    try:
        translation_meta = bible.translation_meta()
        canonical_total = translation_meta.get("totalNumberOfVerses")
        canonical_verse_total = int(canonical_total) if canonical_total is not None else None

        groups, books_processed = collect_groups(
            bible,
            book_filter=args.book,
            cache_dir=cache_dir,
            use_cache=use_cache,
            config=config,
            output_path=args.output,
            canonical_verse_total=canonical_verse_total,
        )
    finally:
        bible.close()

    manifest = build_manifest(
        groups,
        min_size=config.min_group_size,
        max_size=config.max_group_size,
        books_processed=books_processed,
        canonical_verse_total=canonical_verse_total,
    )
    write_manifest_atomic(args.output, manifest)

    print()
    print(
        f"Wrote {manifest['stats']['total_groups']} groups "
        f"({manifest['stats']['total_verses']} verses) to {args.output}"
    )
    if canonical_verse_total is not None:
        delta = manifest["stats"]["total_verses"] - canonical_verse_total
        print(
            f"Canonical translation total: {canonical_verse_total} "
            f"(delta: {delta:+d})"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
