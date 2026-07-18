#!/usr/bin/env python3
"""Assign per-chapter visual themes for manifest verse groups."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from src.runtime import ensure_pipeline_python

ensure_pipeline_python()

from dotenv import load_dotenv

from src.bible_client import BibleClient, extract_chapter_text
from src.config import (
    CHAPTER_CACHE_DIR,
    DEFAULT_MANIFEST,
    DEFAULT_THEMES,
    PROMPTS_DIR,
    THEME_OVERRIDES,
    THEME_REGISTRY,
)
from src.gemini_client import generate_gemini_text
from src.theme_assigner import (
    assign_theme_for_chapter,
    assignment_to_payload,
    should_skip_chapter,
    unique_chapters_from_manifest,
    validate_assignment,
    write_themes_atomic,
)
from src.theme_resolver import load_registry


def _matches_book_filter(book: str, book_filter: str | None) -> bool:
    if book_filter is None:
        return True
    return book.casefold() == book_filter.casefold()


def assign_themes_for_manifest(
    manifest: dict,
    *,
    bible: BibleClient,
    registry_path: Path = THEME_REGISTRY,
    themes_path: Path = DEFAULT_THEMES,
    overrides_path: Path = THEME_OVERRIDES,
    cache_dir: Path | None = None,
    use_cache: bool = True,
    book_filter: str | None = None,
    force: bool = False,
    use_gemini: bool = True,
) -> int:
    registry = load_registry(registry_path)
    chapters = unique_chapters_from_manifest(manifest)
    assigned = 0

    for book, chapter in chapters:
        if not _matches_book_filter(book, book_filter):
            continue
        if should_skip_chapter(
            book,
            chapter,
            themes_path=themes_path,
            overrides_path=overrides_path,
            force=force,
        ):
            print(f"Skipping {book} {chapter} (already assigned or overridden)")
            continue

        book_id = bible.resolve_book_id(book)
        chapter_payload = bible.fetch_chapter_cached(
            book_id,
            chapter,
            cache_dir=cache_dir,
            use_cache=use_cache,
        )
        chapter_text = extract_chapter_text(chapter_payload)

        gemini_generate = generate_gemini_text if use_gemini else None
        assignment, source = assign_theme_for_chapter(
            book=book,
            chapter=chapter,
            chapter_text=chapter_text,
            registry=registry,
            gemini_generate=gemini_generate,
        )
        validate_assignment(assignment, registry)

        write_themes_atomic(
            themes_path,
            {book: {str(chapter): assignment_to_payload(assignment)}},
        )
        assigned += 1
        print(
            f"Assigned {book} {chapter}: {assignment.theme_id} "
            f"({assignment.style}) via {source}"
        )

    return assigned


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Assign per-chapter visual themes for verse groups in a manifest.",
    )
    parser.add_argument(
        "--manifest",
        type=Path,
        default=DEFAULT_MANIFEST,
        help="Path to manifest JSON from group_bible.py",
    )
    parser.add_argument(
        "--themes",
        type=Path,
        default=DEFAULT_THEMES,
        help="Output path for assigned themes JSON",
    )
    parser.add_argument(
        "--registry",
        type=Path,
        default=THEME_REGISTRY,
        help="Path to theme registry JSON",
    )
    parser.add_argument(
        "--overrides",
        type=Path,
        default=THEME_OVERRIDES,
        help="Path to manual theme overrides JSON",
    )
    parser.add_argument(
        "--book",
        help='Process only one book, e.g. "John"',
    )
    parser.add_argument(
        "--cache-dir",
        type=Path,
        default=CHAPTER_CACHE_DIR,
        help="Directory for cached chapter JSON",
    )
    parser.add_argument(
        "--no-cache",
        action="store_true",
        help="Always fetch chapters from the API (do not read or write cache)",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Re-assign chapters even if themes.json already has an entry",
    )
    parser.add_argument(
        "--rules-only",
        action="store_true",
        help="Use deterministic rules only (skip Gemini for unmatched chapters)",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    load_dotenv()
    parser = build_parser()
    args = parser.parse_args(argv)

    manifest = json.loads(args.manifest.read_text(encoding="utf-8"))
    use_cache = not args.no_cache
    cache_dir = None if args.no_cache else args.cache_dir

    bible = BibleClient()
    try:
        assigned = assign_themes_for_manifest(
            manifest,
            bible=bible,
            registry_path=args.registry,
            themes_path=args.themes,
            overrides_path=args.overrides,
            cache_dir=cache_dir,
            use_cache=use_cache,
            book_filter=args.book,
            force=args.force,
            use_gemini=not args.rules_only,
        )
    finally:
        bible.close()

    if assigned == 0:
        print("No chapters assigned.")
    else:
        print(f"\nAssigned {assigned} chapter theme(s) to {args.themes}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
