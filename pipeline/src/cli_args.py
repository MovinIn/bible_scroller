from __future__ import annotations

import argparse
from dataclasses import dataclass
from pathlib import Path

from src.config import CHAPTER_CACHE_DIR, DEFAULT_META_PROMPT, DEFAULT_THEMES, OUTPUT_DIR


def join_cli_words(parts: list[str] | None) -> str:
    if not parts:
        return ""
    return " ".join(parts).strip()


@dataclass(frozen=True)
class GenerateOneCliArgs:
    reference: str
    extra: str
    meta_prompt: Path
    themes: Path
    output_dir: Path
    cache_dir: Path
    no_cache: bool


def add_reference_argument(parser: argparse.ArgumentParser) -> None:
    parser.add_argument(
        "reference",
        nargs="+",
        help='Verse reference, e.g. John 3:16-20 (quotes optional in PowerShell)',
    )


def add_extra_argument(parser: argparse.ArgumentParser) -> None:
    parser.add_argument(
        "--extra",
        nargs="*",
        default=[],
        help="Optional creative guidance passed to the meta-prompt (quotes optional)",
    )


def build_generate_one_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Generate one FLUX image for a Bible verse range.",
    )
    add_reference_argument(parser)
    add_extra_argument(parser)
    parser.add_argument(
        "--meta-prompt",
        type=Path,
        default=DEFAULT_META_PROMPT,
        help="Fallback meta-prompt when themes.json is missing",
    )
    parser.add_argument(
        "--themes",
        type=Path,
        default=DEFAULT_THEMES,
        help="Per-chapter themes JSON from assign_themes.py (used when file exists)",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=OUTPUT_DIR,
        help="Directory for generated images",
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
    return parser


def parse_generate_one_argv(argv: list[str] | None = None) -> GenerateOneCliArgs:
    parser = build_generate_one_parser()
    args = parser.parse_args(argv)
    return GenerateOneCliArgs(
        reference=join_cli_words(args.reference),
        extra=join_cli_words(args.extra),
        meta_prompt=args.meta_prompt,
        themes=args.themes,
        output_dir=args.output_dir,
        cache_dir=args.cache_dir,
        no_cache=args.no_cache,
    )
