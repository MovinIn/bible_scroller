#!/usr/bin/env python3
"""Generate a single Bible scroller background image for review."""

from __future__ import annotations

from src.runtime import ensure_pipeline_python

ensure_pipeline_python()

from dotenv import load_dotenv

from src.bible_client import BibleClient
from src.cli_args import parse_generate_one_argv
from src.config import DEFAULT_STOP_POINT, PROMPTS_DIR, THEME_OVERRIDES, THEME_REGISTRY
from src.generate import generate_for_reference
from src.progress import clear_stop_point, write_stop_point
from src.reference import parse_reference
from src.theme_resolver import resolve_generation_theme


def main(argv: list[str] | None = None) -> int:
    load_dotenv()

    args = parse_generate_one_argv(argv)

    reference = parse_reference(args.reference)
    use_cache = not args.no_cache
    cache_dir = None if args.no_cache else args.cache_dir

    print(f"Reference: {args.reference}")

    meta_prompt_path, theme_guidance, resolved = resolve_generation_theme(
        reference.book,
        reference.chapter,
        themes_path=args.themes,
        fallback_meta_prompt=args.meta_prompt,
        registry_path=THEME_REGISTRY,
        overrides_path=THEME_OVERRIDES,
        prompts_dir=PROMPTS_DIR,
    )
    if resolved is not None:
        print(
            f"Theme: {resolved.assignment.theme_id} "
            f"({resolved.assignment.style}, {resolved.source})"
        )
    print(f"Meta-prompt: {meta_prompt_path}")
    print()

    bible = BibleClient()
    try:
        try:
            result = generate_for_reference(
                reference,
                bible=bible,
                extra_guidance=args.extra,
                meta_prompt_path=meta_prompt_path,
                theme_guidance=theme_guidance,
                output_dir=args.output_dir,
                cache_dir=cache_dir,
                use_cache=use_cache,
            )
        except Exception as exc:
            write_stop_point(DEFAULT_STOP_POINT, reference=args.reference, error=str(exc))
            print(f"Generation failed for {args.reference}: {exc}")
            print(f"Stop point saved to {DEFAULT_STOP_POINT}")
            return 1

        print("=== Verse text ===")
        print(result.verse_text)
        print()

        print("=== FLUX prompt (from Gemini) ===")
        print(result.flux_prompt)
        print()

        print("=== Timing ===")
        print(f"Bible API:  {result.bible_ms:.0f} ms")
        print(f"Gemini:     {result.gemini_ms:.0f} ms")
        print(f"FLUX:       {result.flux_ms:.0f} ms")
        print(f"Total:      {result.bible_ms + result.gemini_ms + result.flux_ms:.0f} ms")
        print()
        print(f"Saved image: {result.output_path}")
        clear_stop_point(DEFAULT_STOP_POINT)
        return 0
    finally:
        bible.close()


if __name__ == "__main__":
    raise SystemExit(main())
